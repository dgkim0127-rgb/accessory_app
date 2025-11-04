import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Firebase 사용자 토큰(커스텀 클레임)을 새로고침하는 함수
Future<void> refreshClaims(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인 상태가 아닙니다.')),
    );
    return;
  }

  // ✅ 새 토큰 강제 갱신
  await user.getIdToken(true);

  // ✅ 갱신된 토큰에서 role 값 확인
  final res = await user.getIdTokenResult(true);
  debugPrint('🧾 token.claims = ${res.claims}');

  // ✅ 사용자에게 결과 표시
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('토큰 새로고침 완료 ✅ (role: ${res.claims?['role'] ?? '없음'})')),
  );
}
