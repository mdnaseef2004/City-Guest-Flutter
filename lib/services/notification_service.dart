// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../services/supabase_service.dart';

class NotificationService {
  // Super Admin Emails Whitelist
  static const List<String> superAdminEmails = [
    'mdnaseef2004@gmail.com',
    'shaheenmohammed554@gmail.com',
    'mampadanmujeeb@gmail.com',
  ];

  // Play Crisp, Loud High-Frequency Audio Chime using Web Audio Synthesizer
  static void playNotificationSound({bool isError = false}) {
    if (!kIsWeb) return;
    try {
      final code = isError
          ? '''
            try {
              var ctx = new (window.AudioContext || window.webkitAudioContext)();
              var osc = ctx.createOscillator();
              var gain = ctx.createGain();
              osc.type = 'sine';
              osc.frequency.setValueAtTime(520, ctx.currentTime);
              osc.frequency.exponentialRampToValueAtTime(260, ctx.currentTime + 0.25);
              gain.gain.setValueAtTime(0.45, ctx.currentTime);
              gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.35);
              osc.connect(gain);
              gain.connect(ctx.destination);
              osc.start();
              osc.stop(ctx.currentTime + 0.35);
            } catch(e){}
          '''
          : '''
            try {
              var ctx = new (window.AudioContext || window.webkitAudioContext)();
              var osc = ctx.createOscillator();
              var gain = ctx.createGain();
              osc.type = 'sine';
              osc.frequency.setValueAtTime(960, ctx.currentTime);
              osc.frequency.exponentialRampToValueAtTime(1440, ctx.currentTime + 0.15);
              gain.gain.setValueAtTime(0.4, ctx.currentTime);
              gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);
              osc.connect(gain);
              gain.connect(ctx.destination);
              osc.start();
              osc.stop(ctx.currentTime + 0.4);
            } catch(e){}
          ''';
      js.context.callMethod('eval', [code]);
    } catch (_) {}
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
