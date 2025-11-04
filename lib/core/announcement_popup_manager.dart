// lib/core/announcement_popup_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 공지 팝업 매니저 (Overlay + 오늘하루 억제 + 외부 터치 차단 + 부드러운 입/퇴장 애니메이션)
class AnnouncementPopupManager extends StatefulWidget {
  final Widget child;
  final bool forceTest;

  const AnnouncementPopupManager({
    super.key,
    required this.child,
    this.forceTest = false,
  });

  @override
  State<AnnouncementPopupManager> createState() => _AnnouncementPopupManagerState();
}

class _AnnouncementPopupManagerState extends State<AnnouncementPopupManager> {
  OverlayEntry? _entry;
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system')
          .doc('announcement')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() ?? {};
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _maybeShow(data);
          });
        }
        return widget.child;
      },
    );
  }

  int _todayKey() {
    final now = DateTime.now();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  Future<void> _maybeShow(Map<String, dynamic> data) async {
    if (!mounted || _showing) return;

    final disabled = data['disabled'] == true;
    final title = (data['title'] ?? '').toString().trim();
    final body  = (data['body']  ?? '').toString().trim();
    final rev   = (data['revision'] is int) ? data['revision'] as int : 0;

    if (disabled || (title.isEmpty && body.isEmpty) || rev <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final lastSkipRev = prefs.getInt('ann.skip.rev') ?? -1;
    final lastSkipDay = prefs.getInt('ann.skip.day') ?? -1;
    final today = _todayKey();
    final skipToday = (lastSkipRev == rev) && (lastSkipDay == today);
    if (!widget.forceTest && skipToday) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    _showing = true;
    bool rememberFlag = false;

    _entry = OverlayEntry(
      maintainState: true,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final cardMaxW = (size.width * 0.82).clamp(260.0, 460.0);
        final cardH    = (size.height * 0.46);

        return _PopupHost(
          width: cardMaxW,
          height: cardH,
          title: title,
          body: body,
          onRemember24h: (checked) async {
            rememberFlag = checked;
            if (checked) {
              await prefs.setInt('ann.skip.rev', rev);
              await prefs.setInt('ann.skip.day', _todayKey());
            } else {
              await prefs.remove('ann.skip.rev');
              await prefs.remove('ann.skip.day');
            }
          },
          onRequestClose: () async {
            // X로 닫을 때도 체크되어 있으면 다시 저장(안전)
            if (rememberFlag) {
              await prefs.setInt('ann.skip.rev', rev);
              await prefs.setInt('ann.skip.day', _todayKey());
            }
          },
          onFullyClosed: () {
            // 애니메이션이 완전히 끝난 뒤 Overlay 제거
            try { _entry?.remove(); } catch (_) {}
            _entry = null;
            _showing = false;
          },
        );
      },
    );

    overlay.insert(_entry!);
  }
}

/// 팝업 호스트: 외부 터치 차단 + 등장/퇴장 애니메이션 관리
class _PopupHost extends StatefulWidget {
  final double width;
  final double height;
  final String title;
  final String body;
  final Future<void> Function(bool remember24h) onRemember24h;
  final Future<void> Function() onRequestClose; // 닫기 요청 시(데이터 저장 등)
  final VoidCallback onFullyClosed;             // 퇴장 애니메이션이 끝난 뒤 호출

  const _PopupHost({
    required this.width,
    required this.height,
    required this.title,
    required this.body,
    required this.onRemember24h,
    required this.onRequestClose,
    required this.onFullyClosed,
  });

  @override
  State<_PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends State<_PopupHost> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;   // 위에서 아래로 살짝
  late final Animation<double> _fade;    // 카드 자체 페이드(배경은 투명 유지)

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = CurvedAnimation(parent: _ac, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    _slide = Tween<Offset>(begin: const Offset(0, -0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut, reverseCurve: Curves.easeIn));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut, reverseCurve: Curves.easeIn);

    // 등장
    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await widget.onRequestClose();
    // 퇴장 애니메이션
    await _ac.reverse();
    widget.onFullyClosed();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 외부 터치 완전 차단(투명)
        const Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.transparent,
          ),
        ),
        // 팝업 본체
        Align(
          alignment: const Alignment(0, -0.05),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(_scale),
                child: _PopupCard(
                  width: widget.width,
                  height: widget.height,
                  title: widget.title,
                  body: widget.body,
                  onRemember24h: widget.onRemember24h,
                  onClose: _close,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 실제 카드 UI
class _PopupCard extends StatefulWidget {
  final double width;
  final double height;
  final String title;
  final String body;
  final Future<void> Function(bool remember24h) onRemember24h;
  final VoidCallback onClose;

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

class _PopupCardState extends State<_PopupCard> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,                     // 각진
          border: Border.all(color: Colors.black, width: 1.0), // 얇은 검정 라인
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
            // 내용
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 제목: "공지: 제목"
                  Text(
                    '공지: ${widget.title}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // 본문 (스크롤)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        widget.body,
                        style: const TextStyle(fontSize: 14.5, height: 1.48, color: Colors.black87),
                      ),
                    ),
                  ),

                  const Divider(height: 20, thickness: 1, color: Colors.black12),

                  // 오늘 하루 보지 않기
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (v) async {
                          final val = v ?? false;
                          setState(() => _remember = val);
                          await widget.onRemember24h(val); // 즉시 저장
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                      const Text('오늘 하루 보지 않기'),
                    ],
                  ),
                ],
              ),
            ),

            // 닫기(X): 작고 모서리에 가깝게
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, color: Colors.black54, size: 16),
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
