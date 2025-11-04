// lib/pages/profile_page.dart  ✅ 최종
// - 관리자 도구를 "정사각형 타일"로 통일 + hover 효과
// - [공지 설정] / [전체 공지] 눌렀을 때 각진 직사각형 팝업(GeneralDialog)
// - 테스트 버튼 제거, Cloud Functions region 고정(asia-northeast3)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../auth/auth_gate.dart';
import 'new_post_page.dart';
import 'admin_users_page.dart';
import 'likes_explorer_page.dart';
import 'activity_logs_page.dart';

/// ───────────────────────── 공지 설정(에디터) ─────────────────────────
/// 제목/내용 입력 → 게시 시 revision +1, disabled=false, publishedAt 갱신
Future<void> showAnnouncementEditorDialog(BuildContext context) async {
  final titleC = TextEditingController();
  final bodyC = TextEditingController();

  // 기존 값 로드
  try {
    final doc = await FirebaseFirestore.instance
        .collection('system')
        .doc('announcement')
        .get();
    final m = doc.data() ?? {};
    titleC.text = (m['title'] ?? '').toString();
    bodyC.text = (m['body'] ?? '').toString();
  } catch (_) {}

  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: '닫기',
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, a2, child) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(anim.value),
        child: Opacity(
          opacity: anim.value,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1.2),
                    borderRadius: BorderRadius.zero, // ◻ 각진
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '공지 수정',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleC,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bodyC,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: '내용',
                          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black54,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(64, 36),
                            ),
                            child: const Text('취소'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(88, 36),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero, // ◻ 각진 버튼
                              ),
                            ),
                            child: const Text('게시'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  if (ok != true) return;

  // 저장
  try {
    await FirebaseFirestore.instance.collection('system').doc('announcement').set({
      'title': titleC.text.trim(),
      'body': bodyC.text.trim(),
      'disabled': false,
      'publishedAt': FieldValue.serverTimestamp(),
      'revision': FieldValue.increment(1),
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공지 게시 완료')),
      );
      Navigator.of(context).pop(); // 프로필로 복귀
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시 실패: $e')),
      );
    }
  }
}

/// ───────────────────────── 전체 공지(푸시) ─────────────────────────
/// super 전용
Future<void> _broadcastAll(BuildContext context) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('웹에선 푸시 전송을 지원하지 않아요. 모바일 앱에서 실행해주세요.')),
    );
    return;
  }

  final titleC = TextEditingController(text: '공지');
  final bodyC = TextEditingController(text: '전체 사용자에게 발송된 알림입니다.');

  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: '닫기',
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, a2, child) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(anim.value),
        child: Opacity(
          opacity: anim.value,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1.2),
                    borderRadius: BorderRadius.zero, // ◻ 각진
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '전체 공지 보내기',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleC,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bodyC,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: '내용',
                          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black54,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(64, 36),
                            ),
                            child: const Text('취소'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(88, 36),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero, // ◻ 각진 버튼
                              ),
                            ),
                            child: const Text('보내기'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  if (ok != true) return;

  try {
    // ✅ v2 onCall은 리전 일치를 꼭 맞춰야 함
    final functions =
    FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    final fn = functions.httpsCallable('broadcastAll');
    await fn.call({'title': titleC.text.trim(), 'body': bodyC.text.trim()});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전체 공지 전송 요청 완료')),
      );
    }
  } on FirebaseFunctionsException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전체 공지 실패: ${e.code} / ${e.message}')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전체 공지 실패(기타): $e')),
      );
    }
  }
}

class ProfilePage extends StatelessWidget {
  final String role; // 'user' | 'admin' | 'super'
  const ProfilePage({super.key, this.role = 'user'});

  String _initialOf(User u) {
    final e = u.email ?? '';
    final id = e.split('@').first;
    return id.isNotEmpty ? id.characters.first.toUpperCase() : 'U';
  }

  String _idOf(User u) {
    final e = u.email ?? '';
    final id = e.split('@').first;
    return id.isNotEmpty ? id : 'user';
  }

  /// 각진 + 좁은폭 로그아웃 팝업
  Future<void> _logout(BuildContext context) async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim1.value),
          child: Opacity(
            opacity: anim1.value,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1.2),
                      borderRadius: BorderRadius.zero,
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('로그아웃',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('정말 로그아웃 하시겠어요?',
                            style: TextStyle(fontSize: 13, color: Colors.black87)),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black54,
                                minimumSize: const Size(60, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              child: const Text('취소'),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                                minimumSize: const Size(70, 36),
                                elevation: 0,
                              ),
                              child: const Text('로그아웃'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (ok == true) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
            (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE6E6E6);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    final userDocStream =
    FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        final fsRole = (snap.data?.data()?['role'] as String?)?.toLowerCase();
        final effectiveRole = (fsRole ?? role).toLowerCase();
        final isAdmin = effectiveRole == 'admin' || effectiveRole == 'super';
        final isSuper = effectiveRole == 'super';

        // 타일 목록(지정 순서)
        final tiles = <Widget>[];
        if (isSuper) {
          tiles.addAll([
            _SquareTool(
              icon: Icons.announcement_outlined,
              title: '공지 설정',
              onTap: () => showAnnouncementEditorDialog(context),
            ),
            _SquareTool(
              icon: Icons.campaign_outlined,
              title: '전체 공지',
              onTap: () => _broadcastAll(context),
            ),
          ]);
        }
        tiles.addAll([
          _SquareTool(
            icon: Icons.favorite_outline,
            title: '회원 좋아요 탐색',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LikesExplorerPage()),
            ),
          ),
          _SquareTool(
            icon: Icons.event_note_outlined,
            title: '회원 활동 로그',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActivityLogsPage()),
            ),
          ),
        ]);
        if (isSuper) {
          tiles.add(
            _SquareTool(
              icon: Icons.group_outlined,
              title: '회원 관리',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminUsersPage()),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                // ───── 프로필 상단 ─────
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(border: Border.all(color: line)),
                      child: Center(
                        child: Text(
                          _initialOf(user),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _idOf(user),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (isAdmin)
                                _RectBtn(
                                  icon: Icons.cloud_upload_outlined,
                                  label: '게시물 업로드',
                                  color: Colors.black,
                                  textColor: Colors.white,
                                  height: 28,
                                  minWidth: 110,
                                  iconSize: 14,
                                  fontSize: 11,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const NewPostPage(),
                                      ),
                                    );
                                  },
                                ),
                              _RectBtn(
                                icon: Icons.logout,
                                label: '로그아웃',
                                color: const Color(0xFFF3F3F3),
                                textColor: Colors.black,
                                height: 24,
                                minWidth: 84,
                                iconSize: 12,
                                fontSize: 10,
                                onTap: () => _logout(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(height: 1),

                // ───── 관리자 도구(타일) ─────
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  const Text('관리자 도구', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.4,
                    children: tiles,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ───────────────────────── 공용 버튼 위젯들 ─────────────────────────

class _RectBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final double height;
  final double minWidth;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const _RectBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.height = 40,
    this.minWidth = 96,
    this.iconSize = 16,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
  });

  @override
  State<_RectBtn> createState() => _RectBtnState();
}

class _RectBtnState extends State<_RectBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minWidth),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          opacity: _down ? 0.85 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: const Color(0xFFE6E6E6)),
            ),
            padding: widget.padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: widget.iconSize, color: widget.textColor),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.fontSize,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SquareTool extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _SquareTool({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  State<_SquareTool> createState() => _SquareToolState();
}

class _SquareToolState extends State<_SquareTool> {
  bool _down = false;
  bool _hover = false; // hover 상태

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE6E6E6);

    Color _bg() {
      if (_down) return Colors.grey[200]!;
      if (_hover) return Colors.grey[100]!;
      return Colors.white;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onTap();
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _down ? 0.85 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _bg(),
              border: Border.all(color: line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.black87),
                const SizedBox(height: 10),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
