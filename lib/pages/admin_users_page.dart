// lib/admin/admin_users_page.dart  ✅ 최종 (A안: Functions 기반 고급 회원 관리)
// - superCreateUser가 Auth + users 문서 생성
// - 여기서 users/<uid> 문서에 plainPassword 필드를 직접 저장해서 목록에서 그대로 보여줌
// - 회원 추가 시 비밀번호 입력은 가리지 않음(그냥 TextField)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/functions_client.dart'; // Fx.callWithFallback 사용

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
  String _roleLabel = '일반 회원'; // 드롭다운 표기
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

  // 상단 카드/버튼 애니메이션 상태
  bool _creating = false;
  double _createProgress = 0.0;
  Timer? _progressTimer;

  // 새로 추가된 유저 하이라이트 & 목록 스크롤
  String? _justAddedUid;
  final _listCtrl = ScrollController();

  // ───────── 권한 체크(관리자/최종관리자면 공지 버튼 노출) ─────────
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
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
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

  // 이메일 앞부분만(이름 표기)
  String _nameFromEmail(String? email) {
    if (email == null || email.isEmpty) return '이름 없음';
    final i = email.indexOf('@');
    return i > 0 ? email.substring(0, i) : email;
  }

  // 버튼 진행 애니메이션
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아이디와 비밀번호를 입력하세요.')),
      );
      return;
    }

    setState(() {
      _creating = true;
      _createProgress = 0;
    });
    _startButtonProgress();

    final email = '$id@test.com';
    final role = _roleValue; // user/admin/super

    try {
      // 1) Cloud Functions로 Auth + 기본 users 문서 생성
      final data = await Fx.callWithFallback<Map<String, dynamic>>(
        'superCreateUser',
        data: {'email': email, 'password': pw, 'role': role},
      );
      final uid = (data['uid'] ?? '').toString();

      // 2) 여기서 users/<uid> 문서에 plainPassword 필드 직접 저장 (merge)
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'plainPassword': pw}, SetOptions(merge: true));
      } catch (e) {
        // 저장 실패해도 회원 생성 자체는 유지
        debugPrint('plainPassword 저장 실패: $e');
      }

      _stopButtonProgress(success: true);

      // 입력 리셋
      _idCtrl.clear();
      _pwCtrl.clear();
      setState(() => _justAddedUid = uid);

      // 목록 맨 아래로 스크롤 + 하이라이트 잠깐 유지
      await Future.delayed(const Duration(milliseconds: 150));
      if (_listCtrl.hasClients) {
        await _listCtrl.animateTo(
          _listCtrl.position.maxScrollExtent + 220,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('회원 추가 완료 (uid: $uid)')),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _justAddedUid = null);
      });
    } on FirebaseFunctionsException catch (e) {
      _stopButtonProgress(success: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('추가 실패: ${e.code} / ${e.message ?? ''}')),
      );
    } catch (e) {
      _stopButtonProgress(success: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('추가 실패: $e')),
      );
    }
  }

  Future<void> _changeRole(String uid, String newRoleValue) async {
    try {
      await Fx.callWithFallback<Map<String, dynamic>>(
        'superSetRole',
        data: {'uid': uid, 'role': newRoleValue},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('역할이 변경되었습니다.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('변경 실패: ${e.code} / ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('변경 실패: $e')),
      );
    }
  }

  Future<void> _deleteUser(String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회원 삭제'),
        content: const Text('정말 삭제하시겠습니까? (Auth/Firestore 모두 삭제)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제되었습니다.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: ${e.code} / ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }

  // ───────── 공지 올리기: 시트 열기 ─────────
  Future<void> _openAnnouncementSheet() async {
    final titleC = TextEditingController();
    final bodyC = TextEditingController();
    bool disabled = false;
    bool requireAckEveryTime = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
                      // 헤더
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          '공지 올리기',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                      ),
                      const Divider(height: 1),

                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            children: [
                              TextField(
                                controller: titleC,
                                decoration: const InputDecoration(
                                  labelText: '제목',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: bodyC,
                                maxLines: 8,
                                decoration: const InputDecoration(
                                  labelText: '내용',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text('비활성화(disabled)'),
                                value: disabled,
                                onChanged: (v) => setSheet(() => disabled = v),
                              ),
                              SwitchListTile(
                                title: const Text('매번 확인 요구(requireAckEveryTime)'),
                                value: requireAckEveryTime,
                                onChanged: (v) => setSheet(() => requireAckEveryTime = v),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  side: const BorderSide(color: Color(0xffe6e6e6)),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                child: const Text('닫기'),
                              ),
                            ),
                            const SizedBox(width: 10),
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
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                child: const Text('게시'),
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

  // ───────── 공지 저장(트랜잭션으로 revision+1) ─────────
  Future<void> _publishAnnouncement({
    required String title,
    required String body,
    required bool disabled,
    required bool requireAckEveryTime,
  }) async {
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 입력하세요.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공지 게시 완료')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final code = e.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시 실패: ${e.message ?? code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    final me = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 관리'),
        centerTitle: false,
        actions: [
          if (_roleLoaded && _isAdminOrSuper)
            TextButton.icon(
              onPressed: _openAnnouncementSheet,
              style: TextButton.styleFrom(foregroundColor: Colors.black),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('공지 올리기'),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          // ─── 상단: 회원 추가 카드 ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration:
              BoxDecoration(color: Colors.white, border: Border.all(color: line)),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: _creating ? 15 : 16,
                    ),
                    child: const Text('회원 추가'),
                  ),
                  const SizedBox(height: 12),

                  _ReverseFloatField(
                    controller: _idCtrl,
                    focusNode: _idFocus,
                    label: '아이디',
                    obscure: false,
                  ),
                  const SizedBox(height: 16),

                  // 비밀번호: 가리지 않음
                  _ReverseFloatField(
                    controller: _pwCtrl,
                    focusNode: _pwFocus,
                    label: '비밀번호',
                    obscure: false,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      const Text('역할', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: _roleLabel,
                        items: const [
                          DropdownMenuItem(value: '일반 회원', child: Text('일반 회원')),
                          DropdownMenuItem(value: '관리자', child: Text('관리자')),
                          DropdownMenuItem(value: '최종 관리자', child: Text('최종 관리자')),
                        ],
                        onChanged: (v) => setState(() => _roleLabel = v ?? '일반 회원'),
                      ),
                      const Spacer(),
                      _AddButton(
                        creating: _creating,
                        progress: _createProgress,
                        onPressed: _creating ? null : _addUser,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1, color: line),

          // ─── 회원 목록 ───
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('email')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 1.5));
                }
                if (!snap.hasData) {
                  return const Center(child: Text('데이터가 없습니다.'));
                }
                final docs = snap.data!.docs;

                return ListView.separated(
                  controller: _listCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final data = d.data();
                    final email = (data['email'] ?? '').toString();
                    final roleValue =
                    (data['role'] ?? 'user').toString().toLowerCase();
                    final displayName = _nameFromEmail(email);
                    final isMe = (me?.uid == d.id);
                    final highlight = (d.id == _justAddedUid);

                    // plainPassword 필드 읽기
                    final plainPw = (data['plainPassword'] ?? '').toString();

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: highlight ? const Color(0xFFF9FBFF) : Colors.white,
                        border: Border.all(color: line),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: highlight ? 16 : 15,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(displayName),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    plainPw.isEmpty
                                        ? 'PW: (저장된 비밀번호 없음)'
                                        : 'PW: $plainPw',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DropdownButton<String>(
                            value: roleValue,
                            items: const [
                              DropdownMenuItem(value: 'user', child: Text('일반 회원')),
                              DropdownMenuItem(value: 'admin', child: Text('관리자')),
                              DropdownMenuItem(
                                  value: 'super', child: Text('최종 관리자')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              _changeRole(d.id, v);
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: isMe ? '본인 계정은 삭제 불가' : '삭제',
                            onPressed: isMe ? null : () => _deleteUser(d.id),
                            icon: const Icon(Icons.delete_outline),
                            color: isMe ? Colors.black26 : Colors.redAccent,
                          ),
                        ],
                      ),
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

/// 언더라인 필드 + "라벨이 아래로 이동" 애니메이션
class _ReverseFloatField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool obscure;
  const _ReverseFloatField({
    required this.controller,
    required this.focusNode,
    required this.label,
    this.obscure = false,
  });

  @override
  State<_ReverseFloatField> createState() => _ReverseFloatFieldState();
}

class _ReverseFloatFieldState extends State<_ReverseFloatField> {
  bool get _active =>
      widget.focusNode.hasFocus || widget.controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.focusNode.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.focusNode.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111111);
    const grey400 = Color(0xFFB0B0B0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: widget.obscure,
          style: const TextStyle(color: ink, fontSize: 15),
          decoration: InputDecoration(
            hintText: _active ? null : widget.label,
            hintStyle: const TextStyle(color: grey400, fontSize: 15),
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 8, top: 12),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: grey400, width: 1.0),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: ink, width: 1.2),
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: _active ? 16 : 0,
          margin: const EdgeInsets.only(top: 4),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: _active ? 1 : 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 추가 버튼: 아래로 슥 + % 표시
class _AddButton extends StatelessWidget {
  final bool creating;
  final double progress; // 0.0 ~ 1.0
  final VoidCallback? onPressed;
  const _AddButton({
    required this.creating,
    required this.progress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      transform: Matrix4.identity()..translate(0.0, creating ? 6.0 : 0.0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff111111),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(90, 40),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          style: TextStyle(
            fontSize: creating ? 12 : 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          child: Text(creating ? '$pct%' : '추가'),
        ),
      ),
    );
  }
}
