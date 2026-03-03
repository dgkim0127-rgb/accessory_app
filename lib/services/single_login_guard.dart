// lib/services/single_login_guard.dart ✅ 최종(A안 차단 + 활동표시 분리)
//
// ✅ 로그인 잠금(차단) 목적:
// - A폰이 로그인(잠금 보유) 중이면 → B폰 로그인 시도는 차단(false)
// - 백그라운드여도 "잠금"은 유지 (B폰 계속 불가)
// - 크래시/강제종료 대비: lastSeenAt이 너무 오래되면 잠금 만료로 간주(선택)
//
// ✅ 활동(접속중 표시) 목적:
// - 활동표시는 "lastSeenAt 최근 여부"만 사용 (isLoggedIn 사용 ❌)
//
// users/{uid} 필드
// - role: string
// - isLoggedIn: bool
// - currentDeviceId: string
// - lastLoginAt: Timestamp
// - lastSeenAt: Timestamp  (포그라운드 ping()으로 갱신)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'device_id.dart';

class SingleLoginGuard {
  SingleLoginGuard._();
  static final SingleLoginGuard instance = SingleLoginGuard._();

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  /// ✅ 잠금 TTL
  /// - "A폰 로그인 중이면 B폰 로그인 불가"를 원하면 너무 짧으면 안 됨.
  /// - 추천: 24시간 (원하면 더 늘려도 됨)
  static const Duration _lockTtl = Duration(hours: 24);

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _fs.collection('users').doc(uid);

  /// ✅ 로그인 직후(또는 자동로그인 직후) "잠금 선점/검증"
  /// - 성공: true  → 이 기기 계속 로그인
  /// - 실패: false → 다른 기기가 로그인 중이라 차단
  Future<bool> acquireLock() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final did = await DeviceId.get();
    final docRef = _doc(user.uid);

    try {
      return await _fs.runTransaction<bool>((tx) async {
        final snap = await tx.get(docRef);

        if (!snap.exists || snap.data() == null) {
          tx.set(
            docRef,
            {
              'role': 'user',
              'isLoggedIn': true,
              'currentDeviceId': did,
              'lastLoginAt': FieldValue.serverTimestamp(),
              'lastSeenAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          return true;
        }

        final data = snap.data() as Map<String, dynamic>;
        final bool isLoggedIn = data['isLoggedIn'] == true;
        final String? currentDeviceId = data['currentDeviceId'] as String?;

        final Timestamp? lastSeenTs = data['lastSeenAt'] as Timestamp?;
        final DateTime? lastSeenAt = lastSeenTs?.toDate();

        bool lockStillValid = false;
        if (isLoggedIn &&
            currentDeviceId != null &&
            currentDeviceId.isNotEmpty &&
            lastSeenAt != null) {
          lockStillValid = DateTime.now().difference(lastSeenAt) <= _lockTtl;
        }

        // 🔒 다른 기기가 유효한 잠금 보유 중이면 차단
        if (lockStillValid && currentDeviceId != did) {
          return false;
        }

        // 🔓 잠금 없거나 만료됐거나 같은 기기면 -> 내 기기로 갱신
        tx.set(
          docRef,
          {
            'isLoggedIn': true,
            'currentDeviceId': did,
            'lastLoginAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return true;
      });
    } catch (e) {
      debugPrint('acquireLock error: $e');
      return false;
    }
  }

  /// ✅ 포그라운드에서만 주기 호출 (활동표시용 lastSeenAt 갱신)
  /// - 백그라운드에서는 호출하지 않음 => lastSeenAt이 멈춰서 "접속중"이 꺼짐
  /// - 하지만 잠금(isLoggedIn)은 그대로 유지됨 => 다른 기기 로그인은 계속 차단됨
  Future<void> ping() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _doc(user.uid).set(
        {
          'lastSeenAt': FieldValue.serverTimestamp(),
          // 잠금 유지 안정성
          'isLoggedIn': true,
          'currentDeviceId': await DeviceId.get(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('ping error: $e');
    }
  }

  /// ✅ 명시적 로그아웃 시 잠금 해제 (내 기기일 때만)
  Future<void> releaseLock() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final did = await DeviceId.get();
    final ref = _doc(user.uid);

    try {
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists || snap.data() == null) return;

        final data = snap.data() as Map<String, dynamic>;
        final String? currentDeviceId = data['currentDeviceId'] as String?;

        if (currentDeviceId == did) {
          tx.set(
            ref,
            {
              'isLoggedIn': false,
              'lastLoginAt': FieldValue.serverTimestamp(),
              'lastSeenAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      });
    } catch (e) {
      debugPrint('releaseLock error: $e');
    }
  }
}