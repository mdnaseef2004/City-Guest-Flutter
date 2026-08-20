import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/guest_assignment.dart';
import 'supabase_service.dart';

class AssignmentService {
  static final SupabaseClient _client = SupabaseService.client;

  // Create Task Assignment (Super Admin)
  static Future<GuestAssignment> createAssignment({
    required String guestName,
    String? notes,
    required String assignedTo,
    DateTime? dueDate,
    bool isUrgent = false,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final data = await _client.from('guest_assignments').insert({
      'guest_name': guestName.trim(),
      'notes': notes?.trim(),
      'assigned_to': assignedTo,
      'assigned_by': user.id,
      'status': 'pending',
      'due_date': dueDate?.toIso8601String().split('T')[0],
      'is_urgent': isUrgent,
    }).select('*, profiles_assigned_to:assigned_to(name), profiles_assigned_by:assigned_by(name)').single();

    // Create Notification for Sub Admin
    final title = isUrgent ? '🚨 URGENT GUEST ASSIGNMENT' : '🔔 New Guest Assigned';
    final message = isUrgent
        ? '$guestName requires your IMMEDIATE attention!'
        : '$guestName has been assigned to you.';
    
    await _client.from('app_notifications').insert({
      'user_id': assignedTo,
      'title': title,
      'message': message,
      'type': isUrgent ? 'urgent' : 'info',
    });

    return GuestAssignment.fromJson(data);
  }

  // Get Assignments List
  static Future<List<GuestAssignment>> getAssignments(bool isSuperAdmin) async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];

    var query = _client.from('guest_assignments').select(
      '*, profiles_assigned_to:assigned_to(name), profiles_assigned_by:assigned_by(name)'
    );

    if (!isSuperAdmin) {
      query = query.eq('assigned_to', user.id);
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List).map((json) => GuestAssignment.fromJson(json)).toList();
  }

  // Update Status & Optional Rejection Reason
  static Future<void> updateAssignmentStatus(String id, String status, {String? rejectionReason}) async {
    final Map<String, dynamic> updateData = {'status': status};
    if (rejectionReason != null && rejectionReason.isNotEmpty) {
      try {
        updateData['rejection_reason'] = rejectionReason;
      } catch (_) {}
    }
    await _client
        .from('guest_assignments')
        .update(updateData)
        .eq('id', id);
  }

  // Super Admin Send Reminder
  static Future<void> sendReminder({
    required String assignmentId,
    required String guestName,
    required String assignedTo,
    required String assignedByName,
  }) async {
    final title = '🔔 REMINDER: Assigned Guest Task';
    final message = 'Please update status for assigned task "$guestName". Sent by $assignedByName.';

    await _client.from('app_notifications').insert({
      'user_id': assignedTo,
      'title': title,
      'message': message,
      'type': 'urgent',
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Sub Admin Accept Assignment (In Progress or Waiting for Guest)
  static Future<void> acceptAssignment({
    required String assignmentId,
    required String subStatus, // 'in_progress' or 'waiting_for_guest'
    required String guestName,
    required String assignedBy,
    required String subAdminName,
  }) async {
    await updateAssignmentStatus(assignmentId, subStatus);

    final statusLabel = subStatus == 'waiting_for_guest' ? 'Waiting for Guest 🛋️' : 'In Progress ⏳';
    await _client.from('app_notifications').insert({
      'user_id': assignedBy,
      'title': 'Task Accepted by $subAdminName',
      'message': '$subAdminName accepted task for "$guestName" (Status: $statusLabel).',
      'type': 'info',
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Sub Admin Reject Assignment with Reason
  static Future<void> rejectAssignment({
    required String assignmentId,
    required String reason,
    required String guestName,
    required String assignedBy,
    required String subAdminName,
  }) async {
    await updateAssignmentStatus(assignmentId, 'rejected', rejectionReason: reason);

    await _client.from('app_notifications').insert({
      'user_id': assignedBy,
      'title': '🚨 Task REJECTED by $subAdminName',
      'message': '$subAdminName rejected task for "$guestName". Reason: "$reason"',
      'type': 'urgent',
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Save Guest Entry to Guest Records AND Complete Assignment
  static Future<void> completeAssignmentWithGuestData({
    required String assignmentId,
    required Map<String, dynamic> guestData,
    required String assignedBy,
    required String adminName,
  }) async {
    // 1. Insert into guest_visits
    await _client.from('guest_visits').insert(guestData);

    // 2. Update assignment status to completed
    await updateAssignmentStatus(assignmentId, 'completed');

    // 3. Send notification to Super Admin
    final guestName = guestData['guest_name'] ?? 'Guest';
    await _client.from('app_notifications').insert({
      'user_id': assignedBy,
      'title': '✅ Task Completed & Guest Saved!',
      'message': '$adminName completed task for "$guestName" and saved record to Guest Records.',
      'type': 'info',
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Delete Assignment
  static Future<void> deleteAssignment(String id) async {
    await _client.from('guest_assignments').delete().eq('id', id);
  }
}
