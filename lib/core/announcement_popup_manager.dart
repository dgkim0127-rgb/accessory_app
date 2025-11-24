// lib/core/announcement_popup_manager.dart
//
// Firestore: system/announcement 문서를 구독해서
// 유효한 공지가 있을 때 앱 전체 위에 팝업을 띄우는 매니저.
//
// - disabled == true 면 표시 안 함
// - title, body 둘 다 비어 있으면 표시 안 함
// - revision(정수) 기준 + "오늘 하루 보지 않기" 체크 지원
// - main.dart 에서 사용하던 forceTest 플래그 유지

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnnouncementPopupManager extends StatefulWidget {
  final Widget child;
  final bool forceTest;

  const AnnouncementPopupManager({
    super.key,
    required this.child,
    this.forceTest = false,
  });

  @override
  State<AnnouncementPopupManager> createState() =>
      _AnnouncementPopupManagerState();
}

class _AnnouncementPopupManagerState extends State<AnnouncementPopupManager> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  OverlayEntry? _entry;
  bool _showing = false;

  static const _kSkipRevKey = 'ann.skip.rev';
  static const _kSkipDayKey = 'ann.skip.day';

  @override
  void initState() {
    super.initState();
    _listenAnnouncement();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hidePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 팝업은 Overlay 로 따로 띄우고,
    // 여기서는 그냥 child 만 반환
    return widget.child;
  }

  void _listenAnnouncement() {
    _sub = FirebaseFirestore.instance
        .collection('system')
        .doc('announcement')
        .snapshots()
        .listen(_onSnapshot, onError: (e) {
      debugPrint('📢 announcement listen error: $e');
    });
  }

  int _todayKey() {
    final now = DateTime.now();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  Future<void> _onSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) async {
    if (!mounted) return;

    if (!snap.exists) {
      _hidePopup();
      return;
    }

    final data = snap.data() ?? {};

    final disabled = data['disabled'] == true;
    final rawTitle = (data['title'] ?? '').toString();
    final rawBody = (data['body'] ?? '').toString();
    final title = rawTitle.trim();
    final body = rawBody.trim();
    final rev =
    (data['revision'] is int) ? data['revision'] as int : 0;

    // 기본 유효성 검사
    if (disabled || (title.isEmpty && body.isEmpty) || rev <= 0) {
      _hidePopup();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastSkipRev = prefs.getInt(_kSkipRevKey) ?? -1;
    final lastSkipDay = prefs.getInt(_kSkipDayKey) ?? -1;
    final today = _todayKey();

    final skipToday =
        (lastSkipRev == rev) && (lastSkipDay == today);

    if (!widget.forceTest && skipToday) {
      // 오늘 이미 건너뛴 동일 revision 이면 안 띄움
      _hidePopup();
      return;
    }

    _showPopup(
      title: title,
      body: body,
      rev: rev,
      prefs: prefs,
      todayKey: today,
    );
  }

  void _showPopup({
    required String title,
    required String body,
    required int rev,
    required SharedPreferences prefs,
    required int todayKey,
  }) {
    if (!mounted) return;

    // 이미 떠 있으면 한 번 지우고 다시
    _hidePopup();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    bool rememberFlag = false;

    _entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final cardMaxW = (size.width * 0.82).clamp(260.0, 460.0);
        final cardH = (size.height * 0.46);

        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // 배경: 어두운 반투명 + 탭하면 닫기
              GestureDetector(
                onTap: () async {
                  if (rememberFlag) {
                    await prefs.setInt(_kSkipRevKey, rev);
                    await prefs.setInt(_kSkipDayKey, todayKey);
                  }
                  _hidePopup();
                },
                child: Container(color: Colors.black54),
              ),

              // 중앙 카드
              Align(
                alignment: const Alignment(0, -0.05),
                child: _PopupCard(
                  width: cardMaxW,
                  height: cardH,
                  title: title,
                  body: body,
                  onRemember24h: (checked) async {
                    rememberFlag = checked;
                    if (checked) {
                      await prefs.setInt(_kSkipRevKey, rev);
                      await prefs.setInt(_kSkipDayKey, todayKey);
                    } else {
                      await prefs.remove(_kSkipRevKey);
                      await prefs.remove(_kSkipDayKey);
                    }
                  },
                  onClose: () async {
                    if (rememberFlag) {
                      await prefs.setInt(_kSkipRevKey, rev);
                      await prefs.setInt(_kSkipDayKey, todayKey);
                    }
                    _hidePopup();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_entry!);
    _showing = true;
  }

  void _hidePopup() {
    if (_entry != null) {
      try {
        _entry!.remove();
      } catch (_) {}
      _entry = null;
    }
    _showing = false;
  }
}

/// 실제 공지 카드 UI (각진 흰배경 + 검은 라인 + "오늘 하루 보지 않기")
class _PopupCard extends StatefulWidget {
  final double width;
  final double height;
  final String title;
  final String body;
  final Future<void> Function(bool remember24h) onRemember24h;
  final Future<void> Function() onClose; // 🔁 여기 타입을 Future<void>로!

  const _PopupCard({
    required this.width,
    required this.height,
    required this.title,
    required this.body,
    required this.onRemember24h,
    required this.onClose,
  });

  @override
  State<_PopupCard> createState() => _PopupCardState();
}

class _PopupCardState extends State<_PopupCard>
    with SingleTickerProviderStateMixin {
  bool _remember = false;
  late final AnimationController _ac;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = CurvedAnimation(
      parent: _ac,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ac,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );
    _fade = CurvedAnimation(
      parent: _ac,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    // onClose 안에서 SharedPreferences 정리 + Overlay 제거 수행
    try {
      await widget.onClose();
    } catch (_) {}
    // onClose 가 먼저 overlay 제거하고 나서 reverse 해도 문제는 없음
    try {
      await _ac.reverse();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111111);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(_scale),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.black, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.20),
                    blurRadius: 10,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding:
                    const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '공지',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (widget.title.isNotEmpty) ...[
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Expanded(
                          child: SingleChildScrollView(
                            padding:
                            const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              widget.body,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.45,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        const Divider(
                          height: 20,
                          thickness: 1,
                          color: Color(0xFFDCDCDC),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Checkbox(
                              value: _remember,
                              onChanged: (v) async {
                                final val = v ?? false;
                                setState(() => _remember = val);
                                await widget.onRemember24h(val);
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '오늘 하루 보지 않기',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      onPressed: _close,
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.black54,
                      ),
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
