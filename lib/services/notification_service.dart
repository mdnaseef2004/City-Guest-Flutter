import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../config/constants.dart';
import '../services/supabase_service.dart';
import 'audio_helper.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();

  // Super Admin Emails Whitelist
  static const List<String> superAdminEmails = [
    'mdnaseef2004@gmail.com',
    'shaheenmohammed554@gmail.com',
    'mampadanmujeeb@gmail.com',
  ];

  // Initialize OneSignal Push Notifications (Works when app is completely closed / swiped away!)
  static Future<void> initOneSignal(String oneSignalAppId) async {
    if (kIsWeb) return;
    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(oneSignalAppId);
      OneSignal.Notifications.requestPermission(true);

      // Handle notification click when user taps system status bar alert (even when app was closed)
      OneSignal.Notifications.addClickListener((event) {
        selectNotificationStream.add('notifications');
      });
    } catch (_) {}
  }

  // Initialize System Notifications
  static Future<void> initLocalNotifications() async {
    if (kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        selectNotificationStream.add(response.payload ?? 'notifications');
      },
    );

    // Request Android 13+ Notification Permission
    final androidPlugin = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  // Show System Notification in Phone Status Bar with Sound & Vibration
  static Future<void> showSystemNotification({
    required String title,
    required String message,
    String payload = 'notifications',
  }) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'city_guest_channel_v2',
      'City Guest Notifications',
      channelDescription: 'Realtime notifications for City Guest tasks and updates',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    final notificationId = (DateTime.now().millisecondsSinceEpoch % 100000).toInt();
    await _localNotificationsPlugin.show(
      notificationId,
      title,
      message,
      details,
      payload: payload,
    );
  }

  // Play Crisp, Loud High-Frequency Audio Chime using Web Audio Synthesizer
  static void playNotificationSound({bool isError = false}) {
    if (!kIsWeb) return;
    playAudioSynth(isError: isError);
  }

  // Show Prominent Popup Notification Banner Overlay Card + Play Loud Chime Sound
  static void showNotificationPopup(
    BuildContext context, {
    required String title,
    required String message,
    bool isError = false,
    IconData? icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Play loud notification sound
    playNotificationSound(isError: isError);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: duration,
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF047857),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? (isError ? Icons.error_outline_rounded : Icons.notifications_active_rounded),
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Insert Notification into database for permanent storage in Notification Centre
  static Future<void> saveNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'info',
  }) async {
    try {
      await SupabaseService.client.from('app_notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'type': type,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // Notify Super Admins when a Sub Admin or Admin adds a guest
  static Future<void> notifyGuestAdded({
    required String adminName,
    required String guestName,
    required String place,
  }) async {
    final currentUserId = SupabaseService.currentUser?.id;
    final message = '$adminName has added a new guest: $guestName from $place.';
    const title = 'New Guest Recorded';

    try {
      // Fetch all profile IDs for super admins
      final profiles = await SupabaseService.client
          .from('profiles')
          .select('id, email');

      for (final p in (profiles as List)) {
        final id = p['id']?.toString();
        final email = p['email']?.toString().toLowerCase().trim() ?? '';

        if (id != null && (superAdminEmails.contains(email) || id == currentUserId)) {
          await saveNotification(
            userId: id,
            title: title,
            message: message,
            type: 'info',
          );
        }
      }
    } catch (_) {}
  }

  // Notify assigned user when a new assignment is created
  static Future<void> notifyAssignmentCreated({
    required String assignedUserId,
    required String assignmentTitle,
    required String assignedByName,
  }) async {
    final message = 'New assignment assigned to you by $assignedByName: "$assignmentTitle".';
    const title = 'New Task Assignment';

    await saveNotification(
      userId: assignedUserId,
      title: title,
      message: message,
      type: 'urgent',
    );
  }

  // Send notification to all Super Admins
  static Future<void> notifySuperAdmins({
    required String title,
    required String message,
    String type = 'info',
  }) async {
    try {
      final profiles = await SupabaseService.client.from('profiles').select('id, email, role');
      for (final p in (profiles as List)) {
        final id = p['id']?.toString();
        final email = p['email']?.toString().toLowerCase().trim() ?? '';
        final role = p['role']?.toString();

        if (id != null && (role == 'super_admin' || superAdminEmails.contains(email))) {
          await saveNotification(
            userId: id,
            title: title,
            message: message,
            type: type,
          );
        }
      }
    } catch (_) {}
  }

  // Notify Super Admins when an Admin or Sub Admin adds an Event
  static Future<void> notifyEventAdded({
    required String adminName,
    required String eventName,
    required String place,
  }) async {
    final currentUserId = SupabaseService.currentUser?.id;
    final message = '$adminName has added a new event: "$eventName" at $place.';
    const title = 'New Event Recorded';

    try {
      final profiles = await SupabaseService.client.from('profiles').select('id, email, role');
      for (final p in (profiles as List)) {
        final id = p['id']?.toString();
        final email = p['email']?.toString().toLowerCase().trim() ?? '';
        final role = p['role']?.toString();

        if (id != null && (role == 'super_admin' || superAdminEmails.contains(email) || id == currentUserId)) {
          await saveNotification(
            userId: id,
            title: title,
            message: message,
            type: 'info',
          );
        }
      }
    } catch (_) {}
  }

  // Super Admin sends Remark / Thank You Comment to an Admin or Sub Admin
  static Future<void> sendRemarkToSubAdmin({
    required String subAdminUserId,
    required String remarkText,
    required String superAdminName,
    String? taskName,
  }) async {
    final title = taskName != null ? '💬 Remark on Task: "$taskName"' : '💬 Message from Super Admin';
    final message = '$superAdminName: "$remarkText"';

    await saveNotification(
      userId: subAdminUserId,
      title: title,
      message: message,
      type: 'info',
    );
  }

  // Super Admin sends Remark / Feedback Comment on Guest or Event Record to Admin
  static Future<void> sendRemarkToAdmin({
    required String targetUserId,
    required String remarkText,
    required String superAdminName,
    required String recordTitle,
  }) async {
    final title = '💬 Super Admin Remark on "$recordTitle"';
    final message = '$superAdminName: "$remarkText"';

    await saveNotification(
      userId: targetUserId,
      title: title,
      message: message,
      type: 'info',
    );
  }

  // Notify file download or upload operation result
  static void notifyFileAction(
    BuildContext context, {
    required String actionLabel,
    required String filename,
    bool isSuccess = true,
    String? errorMessage,
  }) {
    if (isSuccess) {
      showNotificationPopup(
        context,
        title: 'Success!',
        message: 'Successfully $actionLabel "$filename"',
        isError: false,
        icon: Icons.check_circle_rounded,
      );
    } else {
      showNotificationPopup(
        context,
        title: 'Action Failed',
        message: 'Failed to $actionLabel "$filename": ${errorMessage ?? "Unknown error"}',
        isError: true,
        icon: Icons.error_outline_rounded,
      );
    }
  }
}
