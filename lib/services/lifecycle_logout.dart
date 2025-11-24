// lib/services/lifecycle_logout.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'single_login_guard.dart';

/// 앱이 백그라운드로 간 뒤 일정 시간 지나면 자동 로그아웃.
/// 또한 detached(종료 직전) 상태에서도 로그아웃을 시도합니다.
class LifecycleLogout with WidgetsBindingObserver {
  LifecycleLogout._();
  static final LifecycleLogout instance = LifecycleLogout._();

  /// 백그라운드 진입 후 이 시간이 지나면 자동 로그아웃 처리
  static const int _graceSec = 3;

  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    _cancelTimer();
    WidgetsBinding.instance.removeObserver(this);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _signOut() async {
    _cancelTimer();
    try {
      // 🔐 Firestore 상의 단일 로그인 락 해제
      await SingleLoginGuard.instance.releaseLock();
      // Firebase Auth 로그아웃
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 화면을 벗어남(홈 키/앱 전환 등)
    if (state == AppLifecycleState.paused) {
      _cancelTimer();
      _timer = Timer(const Duration(seconds: _graceSec), _signOut);
    }
    // 다시 앞으로 옴 → 로그아웃 타이머 취소
    if (state == AppLifecycleState.resumed) {
      _cancelTimer();
    }
    // 안드로이드에서 종료 직전 등
    if (state == AppLifecycleState.detached) {
      _signOut();
    }
  }
}
