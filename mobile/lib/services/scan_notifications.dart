import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ScanNotifications {
  ScanNotifications._();

  static const _enabled = bool.fromEnvironment('MELODISCAN_FCM_ENABLED');
  static const _channel = AndroidNotificationChannel(
    'scan_results',
    'Résultats des analyses',
    description: 'Notifications lorsque l’analyse d’une partition est terminée.',
    importance: Importance.max,
  );
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!_enabled || _initialized || kIsWeb) return;

    await Firebase.initializeApp();
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) {},
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    _initialized = true;
  }

  static Future<String?> tokenForScan() async {
    if (!_enabled || kIsWeb) return null;

    await initialize();
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return null;
    }
    // Firebase Admin's messaging.Message.token requires an FCM registration token.
    // ignore: deprecated_member_use
    return FirebaseMessaging.instance.getToken();
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: message.messageId.hashCode,
      title: notification.title ?? 'MelodiScan',
      body: notification.body ?? 'Une analyse est terminée.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'scan_results',
          'Résultats des analyses',
          channelDescription:
              'Notifications lorsque l’analyse d’une partition est terminée.',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: message.data['task_id'],
    );
  }
}
