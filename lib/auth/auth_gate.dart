import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../pages/root_tab.dart';
import 'login_page.dart'; // 네 로그인 페이지 경로 유지

/// 로그인 상태 관찰 → (클레임/Firestore) role 로딩 → RootTab(role) 진입
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;

    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _GateLoading();
        }

        final user = authSnap.data;
        if (user == null) return const LoginPage();

        // 1) 커스텀 클레임 우선(최신 토큰 강제 갱신)
        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(true),
          builder: (context, tokenSnap) {
            if (tokenSnap.connectionState == ConnectionState.waiting) {
              return const _GateLoading();
            }

            String finalRole = 'user';
            final claims = tokenSnap.data?.claims ?? {};
            final claimRole = (claims['role'] as String?)?.trim();
            final isAdminFlag = claims['admin'] == true;

            if (claimRole != null && claimRole.isNotEmpty) {
              finalRole = claimRole; // 'admin' | 'super' | 'user' …
            } else if (isAdminFlag) {
              finalRole = 'admin';
            }

            // 2) Firestore users/{uid}.role 로 보강(실시간)
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userDocSnap) {
                if (userDocSnap.connectionState == ConnectionState.waiting) {
                  return const _GateLoading();
                }
                final fsRole =
                (userDocSnap.data?.data()?['role'] as String?)?.trim();

                if ((claimRole == null || claimRole.isEmpty) &&
                    fsRole != null &&
                    fsRole.isNotEmpty) {
                  finalRole = fsRole;
                }

                return RootTab(role: finalRole);
              },
            );
          },
        );
      },
    );
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
    );
  }
}
