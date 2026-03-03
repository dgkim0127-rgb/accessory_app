// lib/main.dart ✅ 최종
import 'package:accessory_app/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth/auth_gate.dart';
import 'core/activity_logger.dart';
import 'core/announcement_popup_manager.dart';
import 'core/app_settings_scope.dart';
import 'core/app_settings_singleton.dart';
import 'firebase_options.dart';
import 'splash/splash_screen.dart';

// ✅ 기존 테마 함수가 app.dart에 있다면 import 유지
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: kIsWeb
        ? DefaultFirebaseOptions.web
        : DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.instance.init();

  // ✅ 로그인/로그아웃 기록
  ActivityLogger.startAuthListener();

  // ✅ 포그라운드/백그라운드(pause/resume) 기록 (세션 초 계속 증가 문제 해결용)
  ActivityLogger.startLifecycleListener();

  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  runApp(
    AppSettingsScope(
      notifier: AppSettings.instance,
      child: const _RootApp(),
    ),
  );
}

class _RootApp extends StatefulWidget {
  const _RootApp({super.key});

  @override
  State<_RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<_RootApp> {
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await FirebaseFirestore.instance.collection('posts').limit(1).get();
    } catch (e) {
      debugPrint('⚠️ Firestore ping failed: $e');
    }

    if (!mounted) return;
    setState(() => _bootstrapped = true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Catalog',
          theme: buildEInkTheme(), // ✅ 기존 테마 유지
          builder: (context, child) {
            final mq = MediaQuery.of(context);

            // ✅ 전역 글자 크기 적용 (textScaleFactor deprecated 해결)
            final scaled = mq.copyWith(
              textScaler: TextScaler.linear(settings.textScale),
            );

            return MediaQuery(
              data: scaled,
              child: AnnouncementPopupManager(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: _bootstrapped ? const AuthGate() : const SplashScreen(),
        );
      },
    );
  }
}