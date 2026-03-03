// lib/core/app_settings_scope.dart
import 'package:flutter/material.dart';
import 'app_settings_singleton.dart';

class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static AppSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope not found in widget tree');
    return scope!.notifier!;
  }
}
