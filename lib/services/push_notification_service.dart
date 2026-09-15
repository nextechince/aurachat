import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'call_notification_service.dart';
import 'call_signaling_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message: ${message.messageId}');

  final data = message.data;
  final type = data['type'] as String?;

  if (type == 'call') {
    try {
      final callService = CallNotificationService();
      await callService.initialize();

      final signal = CallSignal(
        type: CallSignalType.incoming,
        callId: data['call_id'],
        callerId: data['caller_id'],
        callerName: data['caller_name'],
        callerAvatar: data['caller_avatar'],
        channelName: data['channel_name'],
        isVideoCall: data['is_video_call'] == 'true',
      );

      await callService.showIncomingCallNotification(signal);
    } catch (e) {
      debugPrint('Background call notification error (non-fatal): $e');
    }
  }
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  Function(String chatId)? onChatOpen;
  Function()? onNotificationTap;

  // ────────────────────────────────────────────────────────────
  // INIT — every step is try/catch'd so a failure in ANY step
  // doesn't crash the app (fixes the INTERNAL_SERVER_ERROR crash)
  // ────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      await _requestPermission();
    } catch (e) {
      debugPrint('FCM permission error (non-fatal): $e');
    }

    try {
      await _setupLocalNotifications();
    } catch (e) {
      debugPrint('Local notifications setup error (non-fatal): $e');
    }

    // This is the call that was crashing with INTERNAL_SERVER_ERROR
    try {
      await _getAndSaveToken();
    } catch (e) {
      debugPrint('FCM token init error (non-fatal): $e');
    }

    try {
      await CallNotificationService().initialize();
    } catch (e) {
      debugPrint('Call notification init error (non-fatal): $e');
    }

    try {
      _fcm.onTokenRefresh.listen((token) {
        _saveTokenToFirestore(token).catchError((e) {
          debugPrint('Token refresh save error: $e');
        });
      });
    } catch (e) {
      debugPrint('Token refresh listener error (non-fatal): $e');
    }

    try {
      _foregroundSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _openedAppSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    } catch (e) {
      debugPrint('FCM message listeners error (non-fatal): $e');
    }

    try {
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      debugPrint('Initial FCM message error (non-fatal): $e');
    }
  }

  Future<void> _requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: true,
      announcement: false,
      carPlay: false,
    );
    debugPrint('Push notification permission: ${settings.authorizationStatus}');
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction) {
          CallNotificationService().handleNotificationResponse(response);
          return;
        }
        final payload = response.payload;
        if (payload != null) _handlePayload(payload);
      },
    );
  }

  // ────────────────────────────────────────────────────────────
  // TOKEN — the crashing method, now safe
  // ────────────────────────────────────────────────────────────
  Future<void> _getAndSaveToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      // getToken() can throw INTERNAL_SERVER_ERROR transiently.
      // Log it, don't crash.
      debugPrint('FCM getToken failed (non-fatal): $e');
    }
  }

  /// Call this after login to refresh the token
  Future<void> refreshToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('refreshToken failed (non-fatal): $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    String? userId = _auth.currentUser?.uid;
    if (userId == null) {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getString('mock_user_id');
    }

    if (userId == null) {
      debugPrint('No user ID available - cannot save FCM token');
      return;
    }

    try {
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('FCM token saved for user: $userId');
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    try {
      final data = message.data;
      final notification = message.notification;
      final type = data['type'] as String?;

      if (type == 'call') {
        final signal = CallSignal(
          type: CallSignalType.incoming,
          callId: data['call_id'],
          callerId: data['caller_id'],
          callerName: data['caller_name'],
          callerAvatar: data['caller_avatar'],
          channelName: data['channel_name'],
          isVideoCall: data['is_video_call'] == 'true',
        );
        CallNotificationService().showIncomingCallNotification(signal);
        return;
      }

      _showLocalNotification(
        title: notification?.title ?? 'New Message',
        body: notification?.body ?? '',
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('Foreground message handling error (non-fatal): $e');
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    try {
      final data = message.data;
      final type = data['type'] as String?;
      if (type == 'call') return;

      final chatId = data['chatId'];
      if (chatId != null && onChatOpen != null) {
        onChatOpen!(chatId);
      }
      onNotificationTap?.call();
    } catch (e) {
      debugPrint('Notification tap handling error: $e');
    }
  }

  void _handlePayload(String payload) {
    try {
      final data = jsonDecode(payload);
      final chatId = data['chatId'];
      if (chatId != null && onChatOpen != null) {
        onChatOpen!(chatId);
      }
    } catch (e) {
      debugPrint('Error handling notification payload: $e');
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'aura_chat_channel',
        'AURA Chat Messages',
        channelDescription: 'Chat message notifications',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecond,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Show local notification error (non-fatal): $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
    } catch (e) {
      debugPrint('subscribeToTopic error: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
    } catch (e) {
      debugPrint('unsubscribeFromTopic error: $e');
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}
