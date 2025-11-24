// lib/auth/auth_gate.dart  ✅ 최종
// - 로그인 상태 관찰
// - 단일 로그인 가드 + 커스텀 클레임 / Firestore role 로딩
// - 로딩 중에는 언제나 SplashScreen만 표시

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_page.dart';
import '../pages/root_tab.dart';
import '../services/single_login_guard.dart';
import '../splash/splash_screen.dart';
import '../services/notification_service.dart'; // 🔥 추가됨

/// 로그인 상태 관찰 → (단일 로그인 확인) → (클레임/Firestore) role 로딩 → RootTab(role) 진입
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;

    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, authSnap) {
        // 0) FirebaseAuth 연결 중
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        // 1) 로그인 안 된 상태
        final user = authSnap.data;
        if (user == null) {
          return const LoginPage();
        }

        // 2) 단일 로그인 가드 먼저 체크
        return FutureBuilder<bool>(
          future: SingleLoginGuard.instance.acquireLock(),
          builder: (context, lockSnap) {
            if (lockSnap.connectionState == ConnectionState.waiting) {
              return const SplashScreen();
            }

            // 다른 기기에서 이미 로그인 중
            if (lockSnap.data == false) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await FirebaseAuth.instance.signOut();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('이미 다른 기기에서 로그인 중입니다.'),
                  ),
                );
              });
              return const LoginPage();
            }

            // 3) 로그인은 됐고, 단일 로그인도 통과 → 토큰/클레임 로딩
            return FutureBuilder<IdTokenResult>(
              future: user.getIdTokenResult(true),
              builder: (context, tokenSnap) {
                if (tokenSnap.connectionState == ConnectionState.waiting) {
                  return const SplashScreen();
                }

                String finalRole = 'user';
                final claims = tokenSnap.data?.claims ?? {};
                final claimRole = (claims['role'] as String?)?.trim();
                final isAdminFlag = claims['admin'] == true;

                if (claimRole != null && claimRole.isNotEmpty) {
                  finalRole = claimRole; // 'admin' | 'super' | 'user' ...
                } else if (isAdminFlag) {
                  finalRole = 'admin';
                }

                // 4) Firestore users/{uid}.role 실시간 반영
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, userDocSnap) {
                    // Firestore 문서도 아직 안 왔으면 → 스플래시 유지
                    if (userDocSnap.connectionState == ConnectionState.waiting &&
                        !userDocSnap.hasData) {
                      return const SplashScreen();
                    }

                    final fsRole =
                    (userDocSnap.data?.data()?['role'] as String?)?.trim();

                    if ((claimRole == null || claimRole.isEmpty) &&
                        fsRole != null &&
                        fsRole.isNotEmpty) {
                      finalRole = fsRole;
                    }

                    // 🔥 여기서 로그인한 유저 기준으로 FCM 토큰 등록
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      NotificationService.instance.registerForLoggedInUser();
                    });

                    // 🔥 RootTab 렌더링 시작
                    return RootTab(role: finalRole);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
