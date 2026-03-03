// lib/auth/auth_gate.dart ✅ 최종(A안 차단 + 업데이트 체크 1회)
// - acquireLock() 실패하면: signOut + "이미 다른 기기 로그인 중" 표시 + LoginPage
// - 중복 signOut 방지 플래그 포함
// - ✅ 로그인 성공 후 1회: UpdateService.checkAndHandle() 실행(Immediate 인앱 업데이트 우선, 실패 시 스토어 강제 팝업)
//   ※ Firestore system/app 문서는 콘솔에서 만들어두는 걸 권장(자동 생성은 별도 부트스트랩 코드가 필요)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_page.dart';
import '../pages/root_tab.dart';
import '../services/single_login_guard.dart';
import '../splash/splash_screen.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart'; // ✅ 추가

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _handledLockFail = false;

  // ✅ 로그인 상태에서 RootTab 렌더링 후 업데이트 체크를 "한 번만" 실행
  bool _updateChecked = false;

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;

    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        final user = authSnap.data;
        if (user == null) {
          _handledLockFail = false;
          _updateChecked = false; // ✅ 로그아웃 상태면 초기화
          return const LoginPage();
        }

        return FutureBuilder<bool>(
          future: SingleLoginGuard.instance.acquireLock(),
          builder: (context, lockSnap) {
            if (lockSnap.connectionState == ConnectionState.waiting) {
              return const SplashScreen();
            }

            final ok = lockSnap.data == true;
            if (!ok) {
              if (!_handledLockFail) {
                _handledLockFail = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('이미 다른 기기에서 로그인 중입니다.')),
                    );
                  }
                });
              }
              _updateChecked = false; // ✅ 잠금 실패로 로그인 유지 못하면 초기화
              return const LoginPage();
            }

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
                  finalRole = claimRole;
                } else if (isAdminFlag) {
                  finalRole = 'admin';
                }

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, userDocSnap) {
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

                    // ✅ 로그인 후 알림 등록(기존 유지)
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      NotificationService.instance.registerForLoggedInUser();
                    });

                    // ✅ 로그인 성공 후 1회 업데이트 체크 (RootTab 그려진 뒤)
                    if (!_updateChecked) {
                      _updateChecked = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        UpdateService.instance.checkAndHandle(context);
                      });
                    }

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