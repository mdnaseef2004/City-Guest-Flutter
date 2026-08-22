import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

// Top-level background message handler for Firebase Cloud Messaging (FCM)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  try {
    await Firebase.initializeApp();
    final title = message.notification?.title ?? message.data['title'] ?? 'City Guest Alert';
    final body = message.notification?.body ?? message.data['message'] ?? '';
    await NotificationService.showSystemNotification(
      title: title,
      message: body,
      payload: 'notifications',
    );
  } catch (e) {
    debugPrint('Error in FCM background handler: $e');
  }
}

class FirebaseMessagingService {
  static Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      // Initialize Firebase App
      await Firebase.initializeApp();

      // Set background messaging handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // Request User Permission for Push Notifications
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        
        // Retrieve FCM Registration Token for this device
        final fcmToken = await messaging.getToken();
        if (fcmToken != null) {
          debugPrint('FCM Device Token: $fcmToken');
          await _saveTokenToSupabase(fcmToken);
        }

        // Listen for refreshed tokens
        messaging.onTokenRefresh.listen(_saveTokenToSupabase);
      }

      // Handle FCM messages when app is in Foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? message.data['title'] ?? 'City Guest Alert';
        final body = message.notification?.body ?? message.data['message'] ?? '';

        NotificationService.showSystemNotification(
          title: title,
          message: body,
          payload: 'notifications',
        );
      });

      // Handle FCM message tap when app is opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        NotificationService.selectNotificationStream.add('notifications');
      });

    } catch (e) {
      debugPrint('Firebase messaging initialization skipped or failed: $e');
    }
  }

  // Save device FCM Token to Supabase profiles table for targeting notifications
  static Future<void> _saveTokenToSupabase(String token) async {
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId != null) {
        await SupabaseService.client.from('profiles').update({
          'fcm_token': token,
        }).eq('id', userId);
      }
    } catch (_) {}
  }
}
