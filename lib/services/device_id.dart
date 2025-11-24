// lib/services/device_id.dart
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// 설치된 기기마다 1번만 생성되는 고유 deviceId.
/// SharedPreferences에 저장해두고 계속 재사용한다.
class DeviceId {
  static const _key = 'device_id_v1';
  static String? _cached;

  /// 현재 기기의 deviceId를 가져온다. 없으면 새로 생성해서 저장.
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var v = prefs.getString(_key);
    if (v == null || v.isEmpty) {
      v = _generate();
      await prefs.setString(_key, v);
    }
    _cached = v;
    return v;
  }

  static String _generate() {
    final rand = Random();
    String randStr(int n) =>
        List.generate(n, (_) => rand.nextInt(36).toRadixString(36)).join();
    return 'did_${DateTime.now().millisecondsSinceEpoch}_${randStr(6)}';
  }
}
