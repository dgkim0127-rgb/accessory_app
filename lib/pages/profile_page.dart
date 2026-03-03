// lib/pages/profile_page.dart ✅ 최종(모바일 버튼 크게 + 타일 오버플로우 해결)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../auth/auth_gate.dart';
import '../services/single_login_guard.dart';
import 'new_post_page.dart';
import 'admin_users_page.dart';
import 'likes_explorer_page.dart';
import 'activity_logs_page.dart';
import 'settings_page.dart';

Future<void> showAppBarEditorDialog(BuildContext context) async {
  final titleC = TextEditingController();
  final leftUrlC = TextEditingController();
  final rightUrlC = TextEditingController();

  try {
    final doc =
    await FirebaseFirestore.instance.collection('system').doc('appbar').get();
    final m = doc.data() ?? {};
    titleC.text = (m['titleText'] ?? '').toString();
    leftUrlC.text = (m['leftImageUrl'] ?? '').toString();
    rightUrlC.text = (m['rightImageUrl'] ?? '').toString();
  } catch (_) {}

  Future<void> _pickAndUpload({required bool isLeft}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw '업로드할 데이터를 읽을 수 없습니다.';

      final fileName =
          '${isLeft ? 'left' : 'right'}_${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final ref = FirebaseStorage.instance
          .ref()
          .child('system')
          .child('appbar')
          .child(fileName);

      final snap = await ref.putData(bytes);
      final url = await snap.ref.getDownloadURL();

      if (isLeft) {
        leftUrlC.text = url;
      } else {
        rightUrlC.text = url;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 완료: ${isLeft ? '왼쪽' : '오른쪽'}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
      }
    }
  }

  Future<void> _deleteImage({required bool isLeft}) async {
    final url = (isLeft ? leftUrlC.text : rightUrlC.text).trim();
    if (url.isEmpty) return;

    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();

      if (isLeft) {
        leftUrlC.clear();
      } else {
        rightUrlC.clear();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('이미지 삭제 완료')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  final cs = Theme.of(context).colorScheme;
  final line = Theme.of(context).dividerColor;

  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: '닫기',
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) {
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
                    color: cs.surface,
                    border: Border.all(color: line, width: 1.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('앱바 설정',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 14),
                      TextField(
                        controller: titleC,
                        decoration: InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: leftUrlC,
                              readOnly: true,
                              decoration: InputDecoration(
                                hintText: '왼쪽 URL',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _pickAndUpload(isLeft: true),
                            style: ElevatedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(0, 34),
                            ),
                            child: const Text('업로드',
                                style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => _deleteImage(isLeft: true),
                            style: OutlinedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(0, 34),
                            ),
                            child:
                            const Text('삭제', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: rightUrlC,
                              readOnly: true,
                              decoration: InputDecoration(
                                hintText: '오른쪽 URL',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _pickAndUpload(isLeft: false),
                            style: ElevatedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(0, 34),
                            ),
                            child: const Text('업로드',
                                style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => _deleteImage(isLeft: false),
                            style: OutlinedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(0, 34),
                            ),
                            child:
                            const Text('삭제', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('취소')),
                          const SizedBox(width: 8),
                          ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('저장')),
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

  await FirebaseFirestore.instance.collection('system').doc('appbar').set(
    {
      'titleText': titleC.text.trim(),
      'leftImageUrl': leftUrlC.text.trim(),
      'rightImageUrl': rightUrlC.text.trim(),
    },
    SetOptions(merge: true),
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('앱바 저장 완료')));
  }
}

Future<void> showAnnouncementEditorDialog(BuildContext context) async {
  final titleC = TextEditingController();
  final bodyC = TextEditingController();
  bool enabled = true;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('system')
        .doc('announcement')
        .get();
    final m = doc.data() ?? {};
    titleC.text = (m['title'] ?? '').toString();
    bodyC.text = (m['body'] ?? '').toString();
    enabled = !((m['disabled'] as bool?) ?? false);
  } catch (_) {}

  final cs = Theme.of(context).colorScheme;
  final line = Theme.of(context).dividerColor;

  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: '닫기',
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(anim.value),
        child: Opacity(
          opacity: anim.value,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    return Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        border: Border.all(color: line, width: 1.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('공지 설정',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('공지 팝업 띄우기',
                                    style:
                                    TextStyle(fontWeight: FontWeight.w700)),
                              ),
                              Switch(
                                value: enabled,
                                onChanged: (v) => setLocal(() => enabled = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: titleC,
                            decoration: InputDecoration(
                              labelText: '제목',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: bodyC,
                            minLines: 3,
                            maxLines: 6,
                            decoration: InputDecoration(
                              labelText: '내용',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('취소')),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('저장')),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  if (ok != true) return;

  await FirebaseFirestore.instance.collection('system').doc('announcement').set(
    {
      'title': titleC.text.trim(),
      'body': bodyC.text.trim(),
      'disabled': !enabled,
      'publishedAt': FieldValue.serverTimestamp(),
      'revision': FieldValue.increment(1),
    },
    SetOptions(merge: true),
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('공지 저장 완료')));
  }
}

Future<void> _broadcastAll(BuildContext context) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('웹에서는 지원하지 않습니다.')),
    );
    return;
  }

  final titleC = TextEditingController(text: '새로운 소식이 있어요!');
  final bodyC = TextEditingController(text: '지금 앱에서 확인해보세요.');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('전체 푸시 알림'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleC,
              decoration: const InputDecoration(labelText: '제목'),
            ),
            TextField(
              controller: bodyC,
              decoration: const InputDecoration(labelText: '내용'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('보내기')),
        ],
      );
    },
  );

  if (ok != true) return;

  try {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    final fn = functions.httpsCallable('broadcastAll');
    await fn.call({'title': titleC.text.trim(), 'body': bodyC.text.trim()});

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('전송 완료')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('전송 실패: $e')));
    }
  }
}

class ProfilePage extends StatelessWidget {
  final String role;
  const ProfilePage({super.key, this.role = 'user'});

  String _initialOf(User u) {
    final id = (u.email ?? '').split('@').first;
    return id.isNotEmpty ? id.characters.first.toUpperCase() : 'U';
  }

  String _idOf(User u) {
    final id = (u.email ?? '').split('@').first;
    return id.isNotEmpty ? id : 'user';
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃 하시겠어요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('로그아웃')),
        ],
      ),
    );

    if (ok != true) return;

    await SingleLoginGuard.instance.releaseLock();
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final line = theme.dividerColor;
    final isDark = theme.brightness == Brightness.dark;

    final mq = MediaQuery.of(context);
    final bool isMobileLike = mq.size.shortestSide < 600;

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

        final tiles = <Widget>[
          _SquareTool(
            icon: Icons.settings_outlined,
            title: '설정',
            isDark: isDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ];

        if (isSuper) {
          tiles.addAll([
            _SquareTool(
              icon: Icons.palette_outlined,
              title: '앱바',
              isDark: isDark,
              onTap: () => showAppBarEditorDialog(context),
            ),
            _SquareTool(
              icon: Icons.announcement_outlined,
              title: '공지',
              isDark: isDark,
              onTap: () => showAnnouncementEditorDialog(context),
            ),
            _SquareTool(
              icon: Icons.campaign_outlined,
              title: '전체푸시',
              isDark: isDark,
              onTap: () => _broadcastAll(context),
            ),
          ]);
        }

        if (isAdmin || isSuper) {
          tiles.addAll([
            _SquareTool(
              icon: Icons.favorite_outline,
              title: '좋아요',
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LikesExplorerPage()),
              ),
            ),
            _SquareTool(
              icon: Icons.event_note_outlined,
              title: '활동로그',
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivityLogsPage()),
              ),
            ),
          ]);
        }

        if (isSuper) {
          tiles.add(
            _SquareTool(
              icon: Icons.group_outlined,
              title: '회원관리',
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminUsersPage()),
              ),
            ),
          );
        }

        // ✅ 핵심: 모바일에서 타일 높이를 확보(오버플로우 제거)
        final double gridAspect =
        kIsWeb ? 1.8 : (isMobileLike ? 1.28 : 1.85);

        return Scaffold(
          backgroundColor: cs.background,
          body: SafeArea(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 36),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: line, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black38
                            : Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2A2F38)
                              : const Color(0xFFF0F0F0),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _initialOf(user),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _idOf(user),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (isAdmin)
                                  _RectBtn(
                                    icon: Icons.add_photo_alternate_outlined,
                                    label: '업로드',
                                    color: cs.onSurface,
                                    textColor: cs.surface,
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => const NewPostPage()),
                                      );
                                    },
                                  ),
                                _RectBtn(
                                  icon: Icons.logout,
                                  label: '로그아웃',
                                  color: Colors.transparent,
                                  textColor: cs.onSurface.withOpacity(0.7),
                                  borderColor: cs.onSurface.withOpacity(0.2),
                                  onTap: () => _logout(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isAdmin ? '관리자 메뉴' : '서비스 메뉴',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: kIsWeb ? 4 : 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: gridAspect,
                  children: tiles,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RectBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final Color? borderColor;

  const _RectBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.borderColor,
  });

  @override
  State<_RectBtn> createState() => _RectBtnState();
}

class _RectBtnState extends State<_RectBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bool isSmallScreen = mq.size.shortestSide < 600;

    // ✅ 모바일에서 확실히 크게(터치/가독성)
    final double h = isSmallScreen ? 38 : 26;
    final double iconSize = isSmallScreen ? 16 : 13;
    final double fontSize = isSmallScreen ? 13 : 11;
    final double hp = isSmallScreen ? 14 : 10;
    final double gap = isSmallScreen ? 6 : 4;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _down ? 0.96 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: h,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 14),
            border: Border.all(
              color: widget.borderColor ?? Colors.transparent,
              width: 1,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: hp),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: iconSize, color: widget.textColor),
              SizedBox(width: gap),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: fontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareTool extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final VoidCallback onTap;

  const _SquareTool({
    super.key,
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_SquareTool> createState() => _SquareToolState();
}

class _SquareToolState extends State<_SquareTool> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final line = Theme.of(context).dividerColor;

    // ✅ 안전장치: 실제 타일 높이에 맞춰 자동 스케일(오버플로우 방지)
    return LayoutBuilder(
      builder: (context, c) {
        final bool tight = c.maxHeight < 105; // 작은 높이(오버플로우 위험)
        final mq = MediaQuery.of(context);
        final bool isSmallScreen = mq.size.shortestSide < 600;

        // 모바일은 크게 보이되, 높이가 타이트하면 살짝 줄여서 깨끗하게
        final double pad = tight ? 9 : (isSmallScreen ? 11 : 10);
        final double circlePad = tight ? 7 : (isSmallScreen ? 9 : 8);
        final double iconSize = tight ? 18 : (isSmallScreen ? 22 : 18);
        final double titleSize = tight ? 12 : (isSmallScreen ? 13 : 11.5);
        final double gap = tight ? 6 : 8;

        return GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) {
            setState(() => _down = false);
            widget.onTap();
          },
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutBack,
            scale: _down ? 0.96 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1A1D22) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: line, width: 0.5),
                boxShadow: _down
                    ? []
                    : [
                  BoxShadow(
                    color: widget.isDark
                        ? Colors.black38
                        : Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(circlePad),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon,
                        color: cs.onSurface, size: iconSize),
                  ),
                  SizedBox(height: gap),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 2, // ✅ 1줄 고집하면 모바일에서 터짐
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: titleSize,
                      height: 1.05,
                      color: cs.onSurface.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}