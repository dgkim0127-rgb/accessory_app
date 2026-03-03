// lib/pages/admin_users_page.dart ✅ 프리미엄 디자인 적용 (둥근 카드 + 쫀득한 효과 + 다크모드)
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/functions_client.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  // 입력 컨트롤러 & 포커스
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _idFocus = FocusNode();
  final _pwFocus = FocusNode();

  // 역할(표기 ↔ 값)
  String _roleLabel = '일반 회원';
  String get _roleValue {
    switch (_roleLabel) {
      case '관리자':
        return 'admin';
      case '최종 관리자':
        return 'super';
      default:
        return 'user';
    }
  }

  bool _creating = false;
  double _createProgress = 0.0;
  Timer? _progressTimer;

  String? _justAddedUid;
  final _listCtrl = ScrollController();

  bool _roleLoaded = false;
  bool _isAdminOrSuper = false;

  @override
  void initState() {
    super.initState();
    _idFocus.addListener(() => setState(() {}));
    _pwFocus.addListener(() => setState(() {}));
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _roleLoaded = true;
        _isAdminOrSuper = false;
      });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get(const GetOptions(source: Source.server));
      final role = (snap.data()?['role'] ?? 'user').toString().toLowerCase();
      setState(() {
        _roleLoaded = true;
        _isAdminOrSuper = (role == 'admin' || role == 'super');
      });
    } catch (_) {
      setState(() {
        _roleLoaded = true;
        _isAdminOrSuper = false;
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _idFocus.dispose();
    _pwFocus.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  String _nameFromEmail(String? email) {
    if (email == null || email.isEmpty) return '이름 없음';
    final i = email.indexOf('@');
    return i > 0 ? email.substring(0, i) : email;
  }

  void _startButtonProgress() {
    _progressTimer?.cancel();
    _createProgress = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      if (!mounted) return;
      setState(() {
        _createProgress = (_createProgress + 0.02).clamp(0.0, 0.92);
      });
    });
  }

  void _stopButtonProgress({bool success = false}) {
    _progressTimer?.cancel();
    _progressTimer = null;
    setState(() {
      _createProgress = success ? 1.0 : 0.0;
      _creating = false;
    });
    if (success) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() => _createProgress = 0.0);
      });
    }
  }

  Future<void> _addUser() async {
    final id = _idCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (id.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('아이디와 비밀번호를 입력하세요.')));
      return;
    }

    setState(() {
      _creating = true;
      _createProgress = 0;
    });
    _startButtonProgress();

    final email = '$id@test.com';
    final role = _roleValue;

    try {
      final data = await Fx.callWithFallback<Map<String, dynamic>>(
        'superCreateUser',
        data: {'email': email, 'password': pw, 'role': role},
      );
      final uid = (data['uid'] ?? '').toString();

      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({'plainPassword': pw}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('plainPassword 저장 실패: $e');
      }

      _stopButtonProgress(success: true);

      _idCtrl.clear();
      _pwCtrl.clear();
      setState(() => _justAddedUid = uid);

      await Future.delayed(const Duration(milliseconds: 150));
      if (_listCtrl.hasClients) {
        await _listCtrl.animateTo(
          _listCtrl.position.maxScrollExtent + 220,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('회원 추가 완료 (uid: $uid)')));
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _justAddedUid = null);
      });
    } on FirebaseFunctionsException catch (e) {
      _stopButtonProgress(success: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('추가 실패: ${e.code} / ${e.message ?? ''}')));
    } catch (e) {
      _stopButtonProgress(success: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
    }
  }

  Future<void> _changeRole(String uid, String newRoleValue) async {
    try {
      await Fx.callWithFallback<Map<String, dynamic>>(
        'superSetRole',
        data: {'uid': uid, 'role': newRoleValue},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('역할이 변경되었습니다.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('변경 실패: ${e.code} / ${e.message ?? ''}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('변경 실패: $e')));
    }
  }

  Future<void> _deleteUser(String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('회원 삭제', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('정말 삭제하시겠습니까? (복구할 수 없습니다)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await Fx.callWithFallback<Map<String, dynamic>>(
        'superDeleteUser',
        data: {'uid': uid},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: ${e.code} / ${e.message ?? ''}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  Future<void> _openAnnouncementSheet() async {
    final titleC = TextEditingController();
    final bodyC = TextEditingController();
    bool disabled = false;
    bool requireAckEveryTime = true;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: StatefulBuilder(
                builder: (ctx, setSheet) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '공지 올리기',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: cs.onSurface),
                        ),
                      ),
                      Divider(height: 1, color: theme.dividerTheme.color),

                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                          child: Column(
                            children: [
                              TextField(
                                controller: titleC,
                                decoration: InputDecoration(
                                  labelText: '제목',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: bodyC,
                                maxLines: 8,
                                decoration: InputDecoration(
                                  labelText: '내용',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerTheme.color ?? Colors.transparent),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    SwitchListTile(
                                      title: const Text('비활성화(disabled)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      value: disabled,
                                      activeColor: cs.onSurface,
                                      onChanged: (v) => setSheet(() => disabled = v),
                                    ),
                                    Divider(height: 1, color: theme.dividerTheme.color),
                                    SwitchListTile(
                                      title: const Text('매번 확인 요구', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      value: requireAckEveryTime,
                                      activeColor: cs.onSurface,
                                      onChanged: (v) => setSheet(() => requireAckEveryTime = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: theme.dividerTheme.color),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cs.onSurface,
                                  side: BorderSide(color: cs.onSurface.withOpacity(0.2)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('닫기'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  await _publishAnnouncement(
                                    title: titleC.text.trim(),
                                    body: bodyC.text.trim(),
                                    disabled: disabled,
                                    requireAckEveryTime: requireAckEveryTime,
                                  );
                                  if (mounted) Navigator.pop(ctx);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.onSurface,
                                  foregroundColor: theme.scaffoldBackgroundColor,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('게시', style: TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _publishAnnouncement({
    required String title,
    required String body,
    required bool disabled,
    required bool requireAckEveryTime,
  }) async {
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목과 내용을 입력하세요.')));
      return;
    }
    try {
      final ref = FirebaseFirestore.instance.collection('system').doc('announcement');
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        int nextRev = 1;
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>? ?? {};
          final prev = data['revision'];
          if (prev is int) nextRev = prev + 1;
        }
        tx.set(ref, {
          'title': title,
          'body': body,
          'disabled': disabled,
          'requireAckEveryTime': requireAckEveryTime,
          'revision': nextRev,
          'publishedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공지 게시 완료')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('게시 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final me = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        title: Text('회원 관리', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.5)),
        centerTitle: false,
        actions: [
          if (_roleLoaded && _isAdminOrSuper)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _openAnnouncementSheet,
                style: TextButton.styleFrom(foregroundColor: cs.onSurface),
                icon: const Icon(Icons.campaign_outlined, size: 20),
                label: const Text('공지 올리기', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.dividerTheme.color),
        ),
      ),
      body: Column(
        children: [
          // ─── 상단: 프리미엄 회원 추가 카드 ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerTheme.color ?? Colors.transparent, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black45 : Colors.black.withOpacity(0.04),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_add_alt_1, size: 20, color: cs.onSurface.withOpacity(0.8)),
                      const SizedBox(width: 8),
                      Text('새 회원 추가', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _idCtrl,
                    focusNode: _idFocus,
                    decoration: InputDecoration(
                      labelText: '아이디 입력',
                      labelStyle: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _pwCtrl,
                    focusNode: _pwFocus,
                    decoration: InputDecoration(
                      labelText: '비밀번호 입력',
                      labelStyle: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Text('역할 지정', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(0.7))),
                      const SizedBox(width: 12),
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2F38) : const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _roleLabel,
                            dropdownColor: cs.surface,
                            icon: Icon(Icons.expand_more, color: cs.onSurface.withOpacity(0.6), size: 18),
                            items: const [
                              DropdownMenuItem(value: '일반 회원', child: Text('일반 회원', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: '관리자', child: Text('관리자', style: TextStyle(fontSize: 14))),
                              DropdownMenuItem(value: '최종 관리자', child: Text('최종 관리자', style: TextStyle(fontSize: 14))),
                            ],
                            onChanged: (v) => setState(() => _roleLabel = v ?? '일반 회원'),
                          ),
                        ),
                      ),
                      const Spacer(),
                      _AddButton(
                        creating: _creating,
                        progress: _createProgress,
                        onPressed: _creating ? null : _addUser,
                        theme: theme,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ─── 회원 목록 ───
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').orderBy('email').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface));
                }
                if (!snap.hasData) return const Center(child: Text('데이터가 없습니다.'));

                final docs = snap.data!.docs;

                return ListView.separated(
                  controller: _listCtrl,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final data = d.data();
                    final email = (data['email'] ?? '').toString();
                    final roleValue = (data['role'] ?? 'user').toString().toLowerCase();
                    final displayName = _nameFromEmail(email);
                    final isMe = (me?.uid == d.id);
                    final highlight = (d.id == _justAddedUid);
                    final plainPw = (data['plainPassword'] ?? '').toString();

                    return _UserListTile(
                      key: ValueKey(d.id),
                      idLabel: displayName,
                      email: email,
                      plainPw: plainPw,
                      roleValue: roleValue,
                      isMe: isMe,
                      highlight: highlight,
                      isDark: isDark,
                      theme: theme,
                      onChangeRole: (v) => _changeRole(d.id, v),
                      onDelete: () => _deleteUser(d.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 🌟 쫀득하게 눌리는 프리미엄 유저 리스트 타일
class _UserListTile extends StatefulWidget {
  final String idLabel;
  final String email;
  final String plainPw;
  final String roleValue;
  final bool isMe;
  final bool highlight;
  final bool isDark;
  final ThemeData theme;
  final ValueChanged<String> onChangeRole;
  final VoidCallback onDelete;

  const _UserListTile({
    super.key,
    required this.idLabel,
    required this.email,
    required this.plainPw,
    required this.roleValue,
    required this.isMe,
    required this.highlight,
    required this.isDark,
    required this.theme,
    required this.onChangeRole,
    required this.onDelete,
  });

  @override
  State<_UserListTile> createState() => _UserListTileState();
}

class _UserListTileState extends State<_UserListTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    final bgColor = widget.highlight
        ? (widget.isDark ? const Color(0xFF233B5D) : const Color(0xFFF0F6FF))
        : (widget.isDark ? const Color(0xFF1A1D22) : Colors.white);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        scale: _down ? 0.97 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.theme.dividerTheme.color ?? Colors.transparent, width: 0.5),
            boxShadow: _down
                ? []
                : [
              BoxShadow(
                color: widget.isDark ? Colors.black45 : Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.idLabel.isNotEmpty ? widget.idLabel.characters.first.toUpperCase() : 'U',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: cs.onSurface.withOpacity(0.8)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.idLabel,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.plainPw.isEmpty ? 'PW: (없음)' : 'PW: ${widget.plainPw}',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: widget.roleValue,
                    dropdownColor: cs.surface,
                    icon: Icon(Icons.expand_more, size: 16, color: cs.onSurface.withOpacity(0.5)),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('일반', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      DropdownMenuItem(value: 'admin', child: Text('관리자', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      DropdownMenuItem(value: 'super', child: Text('최고관리자', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    ],
                    onChanged: (v) {
                      if (v != null) widget.onChangeRole(v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: widget.isMe ? '본인 삭제 불가' : '삭제',
                onPressed: widget.isMe ? null : widget.onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: widget.isMe ? cs.onSurface.withOpacity(0.1) : Colors.redAccent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 🌟 예쁜 진행률 바가 들어간 추가 버튼
class _AddButton extends StatelessWidget {
  final bool creating;
  final double progress;
  final VoidCallback? onPressed;
  final ThemeData theme;

  const _AddButton({
    required this.creating,
    required this.progress,
    required this.onPressed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;

    return Stack(
      alignment: Alignment.center,
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.onSurface,
            foregroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text(
            creating ? '처리 중' : '추가하기',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (creating)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              ),
            ),
          ),
      ],
    );
  }
}