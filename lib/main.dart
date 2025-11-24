// lib/main.dart  ✅ 최종: 상태바 흰색 + SafeArea 제거(안정적인 B안)
import 'package:accessory_app/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/activity_logger.dart';
import 'core/announcement_popup_manager.dart';
import 'auth/auth_gate.dart';
import 'splash/splash_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: kIsWeb
        ? DefaultFirebaseOptions.web
        : DefaultFirebaseOptions.currentPlatform,
  );

  // 알림 초기화
  await NotificationService.instance.init();

  // 인증 로그 리스너 시작
  ActivityLogger.startAuthListener();

  // 👇 edgeToEdge 안 쓰고, 그냥 상태바/네비바 색만 명시하는 안정적인 방식
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,              // 🔥 상단 바탕 = 흰색
        statusBarIconBrightness: Brightness.dark,  // 아이콘 = 검은색
        statusBarBrightness: Brightness.light,     // (iOS 용)

        systemNavigationBarColor: Colors.white,    // 하단 네비바도 흰색
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  runApp(const _RootApp());
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Catalog',
      theme: buildEInkTheme(),
      builder: (context, child) {
        return AnnouncementPopupManager(
          child: child ?? const SizedBox.shrink(),
        );
      },
      // 👇 SafeArea 완전히 제거 (각 페이지에서 Scaffold가 다 처리)
      home: _bootstrapped
          ? const AuthGate()
          : const SplashScreen(),
    );
  }
}
