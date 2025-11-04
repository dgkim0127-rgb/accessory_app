// lib/auth/login_page.dart ✅ 최종(토큰 강제갱신 + role 디버그 + 안전 처리)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/loading.dart';
import '../core/activity_logger.dart';

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

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
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

      // 1) 로그인
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _pwCtrl.text,
      );

      // 2) ✅ 사용자 리로드(아주 가끔 토큰 재발급 전에 프로필이 오래된 경우 방지)
      await cred.user?.reload();

      // 3) ✅ 커스텀 클레임 강제 반영: 반드시 true로!
      //    이 한 줄이 없으면 role이 예전 값일 수 있어 권한이 계속 막힙니다.
      await cred.user?.getIdToken(true);

      // 4) (선택) 현재 토큰의 role 디버깅
      final token = await cred.user?.getIdTokenResult(true);
      final claimRole = token?.claims?['role'];
      debugPrint('🔐 claims.role = $claimRole');

      hud.setLabel('역할 동기화…');
      hud.stepPercent(0.6);

      // 5) (보조) users/{uid}.role도 확인해서 UI 참고용으로 출력
      final uid = cred.user?.uid;
      if (uid != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
        // 서버 원본 우선 확인 (캐시 착시 방지)
            .get(const GetOptions(source: Source.server));
        final docRole = (snap.data()?['role'] as String?)?.toLowerCase() ?? 'user';
        debugPrint('📌 users/{uid}.role = $docRole');
      }

      // 6) 활동 로그 (실패해도 무시)
      try {
        await ActivityLogger.log('login');
      } catch (_) {}

      hud.setLabel('마무리 중…');
      hud.stepPercent(0.98);
      hud.stepPercent(1.0, label: '완료');

      // 7) 로그인 성공 후 화면 전환(필요 시)
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? '로그인 실패';
    } catch (e) {
      _error = '로그인 실패: $e';
    } finally {
      await LoadingOverlay.hide(context, hud);
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
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), offset: Offset(5, 5), blurRadius: 10),
                    BoxShadow(color: Colors.white, offset: Offset(-5, -5), blurRadius: 10),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 로고
                      const Text(
                        'K',
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
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '아이디를 입력하세요' : null,
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

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ],
                      const SizedBox(height: 32),

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
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

// ───────── 입력 필드 컴포넌트 ─────────
class _UnderlineField extends StatelessWidget {
  final IconData icon;
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool obscure;
  final void Function(String)? onSubmit;

  const _UnderlineField({
    super.key,
    required this.icon,
    required this.controller,
    required this.label,
    this.validator,
    this.obscure = false,
    this.onSubmit,
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
            validator: validator,
            style: const TextStyle(color: ink, fontSize: 15),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: grey400, fontSize: 15),
              floatingLabelStyle:
              const TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 13),
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
