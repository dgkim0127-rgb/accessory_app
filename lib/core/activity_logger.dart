// lib/core/activity_logger.dart ✅ 최종(타입 오류 해결)
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class ActivityLogger {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static StreamSubscription<User?>? _authSub;
  static String? _lastSignedInUid;

  static bool _lifecycleStarted = false;
  static AppLifecycleState? _lastState;
  static DateTime _lastLifecycleLogAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void startAuthListener() {
    _authSub?.cancel();
    _authSub = _auth.authStateChanges().listen((user) async {
      if (user != null) {
        _lastSignedInUid = user.uid;
        await _log('login', uid: user.uid);
      } else {
        final uid = _lastSignedInUid;
        if (uid != null) {
          await _log('logout', uid: uid);
          _lastSignedInUid = null;
        }
      }
    });
  }

  static void startLifecycleListener() {
    if (_lifecycleStarted) return;
    _lifecycleStarted = true;
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
  }

  static Future<void> log(String action, {String? note}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _log(action, uid: uid, note: note);
  }

  static Future<void> safeSignOut() async {
    await logLogout();
    await _auth.signOut();
  }

  static Future<void> logLogin({String? note}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _lastSignedInUid = uid;
    await _log('login', uid: uid, note: note);
  }

  static Future<void> logLogout({String? note}) async {
    final uid = _auth.currentUser?.uid ?? _lastSignedInUid;
    if (uid == null) return;
    await _log('logout', uid: uid, note: note);
  }

  static Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
  }

  static Future<void> _onLifecycle(AppLifecycleState state) async {
    final uid = _auth.currentUser?.uid ?? _lastSignedInUid;
    if (uid == null) return;

    final now = DateTime.now();
    if (_lastState == state && now.difference(_lastLifecycleLogAt).inSeconds < 2) {
      return;
    }
    if (now.difference(_lastLifecycleLogAt).inMilliseconds < 400) return;

    _lastState = state;
    _lastLifecycleLogAt = now;

    if (state == AppLifecycleState.resumed) {
      await _log('resume', uid: uid);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      await _log('pause', uid: uid);
    }
  }

  static Future<void> _log(String action, {required String uid, String? note}) async {
    final user = _auth.currentUser;

    final data = <String, dynamic>{
      'uid': uid,
      'userUid': uid,
      'action': action.toLowerCase(),
      'meta': note ?? '',
      'email': user?.email,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('activity_logs').add(data);

    if (action.toLowerCase() == 'login') {
      await _db.collection('users').doc(uid).set(
        {'lastLoginAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } else {
      await _db.collection('users').doc(uid).set(
        {'lastActivityAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ignore: discarded_futures
    ActivityLogger._onLifecycle(state);
  }
}