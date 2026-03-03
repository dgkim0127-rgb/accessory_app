// lib/auth/login_page.dart ✅ 최종
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/loading.dart';
import '../core/activity_logger.dart';
import '../services/single_login_guard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  String? _error;
  bool _loading = false;

  bool _remember = false;

  static const _kRememberKey = 'login_remember_v1';
  static const _kSavedIdKey = 'login_saved_id_v1';
  static const _kSavedPwKey = 'login_saved_pw_v1';

  @override
  void initState() {
    super.initState();
    _loadSavedLogin();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_kRememberKey) ?? false;
    final savedId = prefs.getString(_kSavedIdKey) ?? '';
    final savedPw = prefs.getString(_kSavedPwKey) ?? '';
    if (!mounted) return;

    setState(() {
      _remember = remember;
      if (remember) {
        _idCtrl.text = savedId;
        _pwCtrl.text = savedPw;
      }
    });
  }

  Future<void> _persistLoginIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (_remember) {
      await prefs.setBool(_kRememberKey, true);
      await prefs.setString(_kSavedIdKey, _idCtrl.text.trim());
      await prefs.setString(_kSavedPwKey, _pwCtrl.text);
    } else {
      await prefs.remove(_kRememberKey);
      await prefs.remove(_kSavedIdKey);
      await prefs.remove(_kSavedPwKey);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final hud = LoadingOverlay.show(context, label: '로그인 준비 중…');
    hud.stepPercent(0.05);

    try {
      final email = "${_idCtrl.text.trim()}@test.com";

      hud.setLabel('계정 확인 중…');
      hud.stepPercent(0.25);

      // 1) Firebase Auth 로그인
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _pwCtrl.text,
      );

      // 2) 🔐 단일 로그인 락 확인
      hud.setLabel('세션 확인 중…');
      hud.stepPercent(0.40);

      final ok = await SingleLoginGuard.instance.acquireLock();
      if (!ok) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        setState(() {
          _error = '이미 다른 기기에서 로그인 중입니다.';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미 다른 기기에서 로그인 중입니다.'),
          ),
        );

        hud.stepPercent(1.0, label: '세션 종료');
        return;
      }

      // 3) 사용자 리로드
      await cred.user?.reload();

      // 4) 커스텀 클레임 강제 반영
      await cred.user?.getIdToken(true);

      // 5) 토큰 role 디버깅
      final token = await cred.user?.getIdTokenResult(true);
      final claimRole = token?.claims?['role'];
      debugPrint('🔐 claims.role = $claimRole');

      hud.setLabel('역할 동기화…');
      hud.stepPercent(0.60);

      // 6) users/{uid}.role 확인
      final uid = cred.user?.uid;
      if (uid != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server));
        final docRole =
            (snap.data()?['role'] as String?)?.toLowerCase() ?? 'user';
        debugPrint('📌 users/{uid}.role = $docRole');
      }

      // 7) 활동 로그 (실패해도 무시)
      try {
        await ActivityLogger.log('login');
      } catch (_) {}

      // 로그인 정보 저장
      await _persistLoginIfNeeded();

      hud.setLabel('마무리 중…');
      hud.stepPercent(0.98);
      hud.stepPercent(1.0, label: '완료');

      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-email') {
        _error = '아이디 또는 비밀번호가 올바르지 않습니다.';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('아이디 또는 비밀번호가 올바르지 않습니다.'),
            ),
          );
        }
      } else if (e.code == 'too-many-requests') {
        _error = '잠시 후 다시 시도해주세요. (로그인 시도 제한)';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('잠시 후 다시 시도해주세요. (로그인 시도 제한)'),
            ),
          );
        }
      } else {
        _error = '로그인 실패: ${e.code}';
      }
    } catch (e) {
      _error = '로그인 실패: $e';
    } finally {
      LoadingOverlay.hideAny();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111111);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        offset: Offset(5, 5),
                        blurRadius: 10),
                    BoxShadow(
                        color: Colors.white,
                        offset: Offset(-5, -5),
                        blurRadius: 10),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'R',
                        style: TextStyle(
                          color: ink,
                          fontSize: 180,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4.0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _UnderlineField(
                        icon: Icons.person_outline,
                        controller: _idCtrl,
                        label: '아이디',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '아이디를 입력하세요'
                            : null,
                        onChanged: (_) {
                          if (_remember) {
                            setState(() {
                              _remember = false;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 28),
                      _UnderlineField(
                        icon: Icons.lock_outline,
                        controller: _pwCtrl,
                        label: '비밀번호',
                        obscure: true,
                        validator: (v) =>
                        (v == null || v.isEmpty) ? '비밀번호를 입력하세요' : null,
                        onSubmit: (_) => _login(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: _remember,
                              onChanged: (v) {
                                setState(() {
                                  _remember = v ?? false;
                                });
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '로그인 정보 저장',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ink,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Text(
                            '로그인',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnderlineField extends StatelessWidget {
  final IconData icon;
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool obscure;
  final void Function(String)? onSubmit;
  final void Function(String)? onChanged;

  const _UnderlineField({
    super.key,
    required this.icon,
    required this.controller,
    required this.label,
    this.validator,
    this.obscure = false,
    this.onSubmit,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111111);
    const grey400 = Color(0xFFB0B0B0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, right: 10),
          child: Icon(icon, color: ink, size: 24),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            onFieldSubmitted: onSubmit,
            onChanged: onChanged,
            validator: validator,
            style: const TextStyle(color: ink, fontSize: 15),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: grey400, fontSize: 15),
              floatingLabelStyle: const TextStyle(
                color: ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: grey400, width: 1.0),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: ink, width: 1.2),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
          ),
        ),
      ],
    );
  }
}