// lib/core/activity_logger.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 로그인/로그아웃을 자동 기록하고,
/// 수동 로그아웃 시에는 반드시 safeSignOut()을 사용해 로그가 선기록되도록 보장.
class ActivityLogger {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static StreamSubscription<User?>? _authSub;
  static String? _lastSignedInUid;

  /// 앱 시작 시 1회 호출 (Firebase init 이후)
  static void startAuthListener() {
    _authSub?.cancel();
    _authSub = _auth.authStateChanges().listen((user) async {
      if (user != null) {
        _lastSignedInUid = user.uid;
        await _log('login', uid: user.uid);
      } else {
        // authStateChanges 로 인한 자동 로그아웃 감지
        if (_lastSignedInUid != null) {
          await _log('logout', uid: _lastSignedInUid);
          _lastSignedInUid = null;
        }
      }
    });
  }

  /// 임의 활동 기록(좋아요/작성 등)
  static Future<void> log(String action, {String? note}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _log(action, uid: uid, note: note);
  }

  /// 명시적 로그인/로그아웃 기록용
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

  /// 안전 로그아웃: 로그 기록 후 signOut
  static Future<void> safeSignOut() async {
    await logLogout();
    await _auth.signOut();
  }

  static Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
  }

  /// 내부 공용 작성기
  static Future<void> _log(String action, {required String? uid, String? note}) async {
    if (uid == null) return;
    final user = _auth.currentUser;

    final data = <String, dynamic>{
      'uid': uid,                       // 조회/규칙용 키
      'userUid': uid,                   // 하위 호환
      'action': action.toLowerCase(),   // 'login' | 'logout' | ...
      'meta': note ?? '',
      'email': user?.email,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('activity_logs').add(data);

    // 보조 정보
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
