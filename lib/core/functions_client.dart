// lib/core/functions_client.dart
import 'package:cloud_functions/cloud_functions.dart';

/// Cloud Functions 헬퍼
/// - 1차: asia-northeast3
/// - 실패 시: default(프로젝트 기본 리전) 로 1회 재시도
class Fx {
  static const String _primaryRegion = 'asia-northeast3';

  static FirebaseFunctions _inst(String? region) {
    return (region == null || region.isEmpty)
        ? FirebaseFunctions.instance
        : FirebaseFunctions.instanceFor(region: region);
  }

  /// 리전 우선 호출 + NOT_FOUND/UNAVAILABLE 시 한 번 더 fallback
  static Future<T> callWithFallback<T>(
      String name, {
        Map<String, dynamic>? data,
        int timeoutSeconds = 25,
      }) async {
    final primary = _inst(_primaryRegion)
        .httpsCallable(name, options: HttpsCallableOptions(timeout: Duration(seconds: timeoutSeconds)));
    try {
      final res = await primary.call<Map<String, dynamic>?>(data);
      // ignore: unnecessary_cast
      return (res.data as dynamic) as T;
    } on FirebaseFunctionsException catch (e) {
      // 리전 미스매치일 때 NOT_FOUND 가 흔합니다.
      final code = e.code.toLowerCase();
      if (code == 'not-found' || code == 'unavailable') {
        final fallback = _inst(null).httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: Duration(seconds: timeoutSeconds)),
        );
        final res2 = await fallback.call<Map<String, dynamic>?>(data);
        // ignore: unnecessary_cast
        return (res2.data as dynamic) as T;
      }
      rethrow;
    }
  }
}
