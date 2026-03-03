// lib/core/app_settings.dart  ✅ 최종 (다크/라이트 제거, 글자크기만)
import 'package:flutter/material.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// 1.0 ~ 1.4 (100% ~ 140%)
  double _textScale = 1.0;

  double get textScale => _textScale;

  void setTextScale(double v) {
    final nv = v.clamp(1.0, 1.4).toDouble();
    if (_textScale == nv) return;
    _textScale = nv;
    notifyListeners();
  }
}
