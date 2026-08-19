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

  // Update Status
  static Future<void> updateAssignmentStatus(String id, String status) async {
    await _client
        .from('guest_assignments')
        .update({'status': status})
        .eq('id', id);
  }

  // Delete Assignment
  static Future<void> deleteAssignment(String id) async {
    await _client.from('guest_assignments').delete().eq('id', id);
  }
}
