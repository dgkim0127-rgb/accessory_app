// lib/main.dart  ✅ 최종: 전역에서 팝업 매니저로 감싸기
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';
import 'auth/login_page.dart';
import 'pages/root_tab.dart';
import 'core/activity_logger.dart';
import 'splash/splash_screen.dart';
import 'core/announcement_popup_manager.dart'; // ← 팝업 매니저(Overlay 버전)

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: kIsWeb
        ? const FirebaseOptions(
      apiKey: "AIzaSyDR0Gq3HwrAfHFfQo8ngrLFNo7YBSLpw5U",
      authDomain: "djvmf-ce8e6.firebaseapp.com",
      projectId: "djvmf-ce8e6",
      storageBucket: "djvmf-ce8e6.firebasestorage.app",
      messagingSenderId: "1028791528109",
      appId: "1:1028791528109:web:709dc56fec1446e5bef424",
      measurementId: "G-6VQSNE9DQN",
    )
        : null,
  );
}

final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _defaultChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: '앱 주요 알림 채널',
  importance: Importance.max,
  playSound: true,
);

Future<void> initPushAndLocalNotifications() async {
  if (kIsWeb) return;

  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true, badge: true, sound: true,
  );
  debugPrint('🔔 Permission: ${settings.authorizationStatus}');

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true, badge: true, sound: true,
  );

  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initIOS = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const initSettings = InitializationSettings(android: initAndroid, iOS: initIOS);
  await _fln.initialize(initSettings);

  final androidImpl =
  _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl != null) {
    await androidImpl.createNotificationChannel(_defaultChannel);
  }

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannel.id, _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.max, priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    await _fln.show(n.hashCode, n.title ?? '알림', n.body ?? '', details);
  });

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  try {
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('📲 FCM token: $token');

    try { await FirebaseMessaging.instance.subscribeToTopic('all'); } catch (_) {}

    final u = FirebaseAuth.instance.currentUser;
    if (u != null && token != null) {
      final usersRef = FirebaseFirestore.instance.collection('users').doc(u.uid);
      await usersRef.set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await usersRef.collection('tokens').doc(token).set({
        'token': token,
        'platform': Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other'),
        'subscribedAll': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('🔄 FCM token refreshed: $newToken');
      final u2 = FirebaseAuth.instance.currentUser;
      if (u2 != null && newToken.isNotEmpty) {
        final usersRef = FirebaseFirestore.instance.collection('users').doc(u2.uid);
        await usersRef.set({
          'fcmToken': newToken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await usersRef.collection('tokens').doc(newToken).set({
          'token': newToken,
          'platform': Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other'),
          'subscribedAll': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        try { await FirebaseMessaging.instance.subscribeToTopic('all'); } catch (_) {}
      }
    });
  } catch (e) {
    debugPrint('⚠️ FCM init error: $e');
  }
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: kIsWeb
          ? const FirebaseOptions(
        apiKey: "AIzaSyDR0Gq3HwrAfHFfQo8ngrLFNo7YBSLpw5U",
        authDomain: "djvmf-ce8e6.firebaseapp.com",
        projectId: "djvmf-ce8e6",
        storageBucket: "djvmf-ce8e6.firebasestorage.app",
        messagingSenderId: "1028791528109",
        appId: "1:1028791528109:web:709dc56fec1446e5bef424",
        measurementId: "G-6VQSNE9DQN",
      )
          : null,
    );
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }
  }

  try {
    await FirebaseFirestore.instance.collection('posts').limit(1).get();
  } catch (e) {
    debugPrint('⚠️ Firestore ping failed: $e');
  }

  await initPushAndLocalNotifications();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootApp());
}

class _BootApp extends StatelessWidget {
  const _BootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ensureFirebaseInitialized(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildEInkTheme(),
            home: const SplashScreen(),
          );
        }
        if (snap.hasError) {
          debugPrint('🔥 Firebase init error: ${snap.error}');
        }
        ActivityLogger.startAuthListener();

        // ✅ 전역(앱 전체)을 팝업 매니저로 감싼다
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Accessory App',
          theme: buildEInkTheme(),

          // ⚠️ 테스트가 급하면 forceTest: true로 켜서 "무조건" 보이게 확인 후 false로 되돌리기
          builder: (context, child) => AnnouncementPopupManager(
            // forceTest: true, // ← 테스트 시만 주석 해제
            child: child ?? const SizedBox.shrink(),
          ),

          home: const SafeArea(child: _AuthGate()),
        );
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const LoginPage();

        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(true),
          builder: (context, tokenSnap) {
            if (tokenSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            String finalRole = 'user';
            final claims = tokenSnap.data?.claims ?? {};
            final claimRole = (claims['role'] as String?)?.trim();
            final isAdminFlag = claims['admin'] == true;
            if (claimRole != null && claimRole.isNotEmpty) {
              finalRole = claimRole;
            } else if (isAdminFlag) {
              finalRole = 'admin';
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userDocSnap) {
                if (userDocSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                final fsRole = (userDocSnap.data?.data()?['role'] as String?)?.trim();
                if ((claimRole == null || claimRole.isEmpty) &&
                    fsRole != null && fsRole.isNotEmpty) {
                  finalRole = fsRole;
                }
                return RootTab(role: finalRole);
              },
            );
          },
        );
      },
    );
  }
}
