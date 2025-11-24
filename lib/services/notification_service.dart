// lib/services/notification_service.dart  ✅ 최종 (B안: 토큰 변경시에만 Firestore 업데이트)
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("🔔 Handling a background message: ${message.messageId}");
}

class NotificationService {
  NotificationService._privateConstructor();
  static final NotificationService instance =
  NotificationService._privateConstructor();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _fln =
  FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _defaultChannel =
  AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: '앱 주요 알림 채널',
    importance: Importance.max,
    playSound: true,
  );

  /// 앱 시작 시 1번만 호출 (main.dart)
  Future<void> init() async {
    if (kIsWeb) return;

    await _requestPermission();
    await _initLocalNotifications();

    _listenForForegroundMessages();

    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    // 여기서는 "디바이스 기준" 설정만. Firestore 저장은 로그인 후 따로.
    await _initTokenManagement();
  }

  // ───────────────── 권한 & 로컬 알림 세팅 ─────────────────

  Future<void> _requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 Permission: ${settings.authorizationStatus}');

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _initLocalNotifications() async {
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initIOS = DarwinInitializationSettings();
    const initSettings =
    InitializationSettings(android: initAndroid, iOS: initIOS);

    await _fln.initialize(initSettings);

    final androidImpl = _fln
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_defaultChannel);
  }

  // 포그라운드 수신 → 로컬 알림
  void _listenForForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      if (n == null) return;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      );

      await _fln.show(
        n.hashCode,
        n.title ?? '알림',
        n.body ?? '',
        details,
      );
    });
  }

  // ───────────────── 토큰 관리(디바이스 기준) ─────────────────

  Future<void> _initTokenManagement() async {
    try {
      // 1) 디바이스 기준 토큰 1번 가져오기
      final token = await _fcm.getToken();
      debugPrint('📲 FCM token (device): $token');

      // 2) all 토픽 구독 (실패해도 무시)
      try {
        await _fcm.subscribeToTopic('all');
      } catch (_) {}

      // 3) 토큰 갱신 리스너 (여기서는 Firestore 안 건드림)
      _fcm.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 FCM token refreshed (device): $newToken');
        try {
          _fcm.subscribeToTopic('all');
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('⚠️ FCM token management error: $e');
    }
  }

  // ───────────────── 로그인된 유저용 등록 ─────────────────

  /// 🔥 로그인한 유저 기준으로 토큰을 Firestore에 저장
  /// AuthGate에서 로그인 완료 후에 매번 호출
  Future<void> registerForLoggedInUser() async {
    if (kIsWeb) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ registerForLoggedInUser: no current user');
        return;
      }

      final token = await _fcm.getToken();
      debugPrint(
          '📲 registerForLoggedInUser token: $token (uid: ${user.uid})');

      if (token != null && token.isNotEmpty) {
        await _saveTokenToFirestore(token);
        try {
          await _fcm.subscribeToTopic('all');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ registerForLoggedInUser error: $e');
    }
  }

  // ───────────────── Firestore 저장 (B안: 토큰 변경시에만) ─────────────────

  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || token.isEmpty) {
      debugPrint('⚠️ _saveTokenToFirestore: user=null or token empty');
      return;
    }

    final userRef =
    FirebaseFirestore.instance.collection('users').doc(user.uid);

    // 1) 이전에 저장된 토큰과 같은지 먼저 확인 (B안 핵심)
    try {
      final snap = await userRef.get();
      final data = snap.data();
      final prevToken = (data?['fcmToken'] as String?) ?? '';

      if (prevToken == token) {
        debugPrint(
            'ℹ️ _saveTokenToFirestore: token unchanged, skip Firestore write.');
        return; // 같은 토큰이면 아무 것도 안 함 → 쓰기 비용 0
      }
    } catch (e) {
      debugPrint('⚠️ _saveTokenToFirestore: read previous token failed: $e');
      // 읽기 실패해도 이어서 새 토큰을 저장하도록 둔다.
    }

    // 2) 토큰이 실제로 변경된 경우에만 저장
    try {
      final tokenRef = userRef.collection('tokens').doc(token);

      final platform = Platform.isIOS
          ? 'ios'
          : (Platform.isAndroid ? 'android' : 'other');

      final tokenData = {
        'token': token,
        'platform': platform,
        'subscribedAll': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // (선택) 상세 토큰 목록 보관 — 나중에 필요 없으면 이 줄은 지워도 됨
      await tokenRef.set(tokenData);

      // users/{uid} 문서에는 "마지막 토큰 + 갱신 시각"만 기록
      await userRef.set(
        {
          'fcmToken': token,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      debugPrint('✅ FCM token saved to Firestore for user ${user.uid}');
    } on FirebaseException catch (e) {
      debugPrint('❌ _saveTokenToFirestore 실패: ${e.message}');
    } catch (e) {
      debugPrint('❌ _saveTokenToFirestore 실패(기타): $e');
    }
  }
}
