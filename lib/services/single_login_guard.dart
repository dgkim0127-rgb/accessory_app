// lib/services/single_login_guard.dart  ✅ 최종
//
// users/{uid} 에 저장되는 필드:
// - role: string        (기본 'user')
// - isLoggedIn: bool    (현재 어떤 기기든 로그인 중인지)
// - currentDeviceId: string (로그인 잠금 잡고 있는 기기 ID)
// - lastLoginAt: Timestamp  (마지막으로 잠금 갱신된 시각)
//
// 동작 요약:
// 1) acquireLock()
//    - 이 계정의 잠금이 비어 있거나, 만료됐거나, 같은 기기면 → 이 기기가 잠금 선점
//    - 다른 기기가 최근에 로그인 중이면 → false (로그인 차단)
// 2) releaseLock()
//    - 이 기기가 잠금을 갖고 있을 때만 isLoggedIn=false 로 해제
//

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'device_id.dart';

class SingleLoginGuard {
  SingleLoginGuard._();
  static final SingleLoginGuard instance = SingleLoginGuard._();

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  /// 이전 로그인으로부터 이 시간(분) 이하이면
  /// "아직 다른 기기에서 로그인 중"으로 간주.
  static const int _lockMinutes = 10;

  /// 현재 로그인된 사용자에 대해 "이 기기"가 세션을 선점하려고 시도.
  /// - 성공: true  → 이 기기에서 로그인 계속 진행
  /// - 실패: false → 다른 기기가 사용 중이라 이 기기는 로그인 불가
  Future<bool> acquireLock() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final did = await DeviceId.get();
    final docRef = _fs.collection('users').doc(user.uid);
    final now = DateTime.now();

    try {
      return await _fs.runTransaction<bool>((tx) async {
        final snap = await tx.get(docRef);

        if (!snap.exists || snap.data() == null) {
          // 사용자 문서가 없으면 기본값으로 생성 후 잠금 선점
          tx.set(
            docRef,
            {
              'role': 'user',
              'isLoggedIn': true,
              'currentDeviceId': did,
              'lastLoginAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          return true;
        }

        final data = snap.data() as Map<String, dynamic>;

        final bool isLoggedIn = (data['isLoggedIn'] == true);
        final String? currentDeviceId = data['currentDeviceId'] as String?;
        final Timestamp? lastLoginAtTs = data['lastLoginAt'] as Timestamp?;
        final DateTime? lastLoginAt = lastLoginAtTs?.toDate();

        bool lockStillValid = false;
        if (isLoggedIn && lastLoginAt != null) {
          final diffMinutes = now.difference(lastLoginAt).inMinutes;
          lockStillValid = diffMinutes < _lockMinutes;
        }

        // 🔒 다른 기기가 아직 유효 시간 안에 로그인 중이면 차단
        if (lockStillValid &&
            currentDeviceId != null &&
            currentDeviceId != did) {
          return false;
        }

        // 🔓 잠금이 없거나, 만료됐거나, 같은 기기면 → 이 기기로 잠금/갱신
        tx.set(
          docRef,
          {
            'isLoggedIn': true,
            'currentDeviceId': did,
            'lastLoginAt': FieldValue.serverTimestamp(),
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

  /// 명시적으로 로그아웃할 때 호출:
  /// 이 기기가 잠금을 가지고 있는 경우에만 해제.
  Future<void> releaseLock() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final did = await DeviceId.get();
    final docRef = _fs.collection('users').doc(user.uid);

    try {
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists || snap.data() == null) return;

        final data = snap.data() as Map<String, dynamic>;
        final String? currentDeviceId = data['currentDeviceId'] as String?;

        // 이 기기가 잠금 주인이면 잠금 해제
        if (currentDeviceId == did) {
          tx.set(
            docRef,
            {
              'isLoggedIn': false,
              'lastLoginAt': FieldValue.serverTimestamp(),
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
