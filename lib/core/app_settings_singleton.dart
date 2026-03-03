// lib/core/app_settings_singleton.dart
import 'package:flutter/foundation.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// 글자 크기 배율: 1.0 ~ 1.4 (100% ~ 140%)
  double _textScale = 1.0;
  double get textScale => _textScale;

  void setTextScale(double v) {
    final next = v.clamp(1.0, 1.4);
    if (next == _textScale) return;
    _textScale = next;
    notifyListeners();
  }
}
