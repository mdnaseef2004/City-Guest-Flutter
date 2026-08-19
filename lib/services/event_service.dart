import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event_model.dart';
import 'supabase_service.dart';

class EventService {
  static final SupabaseClient _client = SupabaseService.client;

  // Add Event
  static Future<EventModel> addEvent({
    required String eventName,
    required String eventPlace,
    required int membersCount,
    required String organizedBy,
    required DateTime eventDate,
    required String handledBy,
    String? remarks,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final data = await _client.from('events').insert({
      'event_name': eventName.trim(),
      'event_place': eventPlace.trim(),
      'members_count': membersCount,
      'organized_by': organizedBy.trim(),
      'event_date': eventDate.toIso8601String().split('T')[0],
      'handled_by': handledBy.trim(),
      'remarks': remarks?.trim(),
      'created_by': user.id,
    }).select().single();

    return EventModel.fromJson(data);
  }

  // Get Events
  static Future<List<EventModel>> getEvents(bool isSuperAdmin) async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];

    var query = _client.from('events').select('*');
    if (!isSuperAdmin) {
      query = query.eq('created_by', user.id);
    }

    final data = await query.order('event_date', ascending: false);
    return (data as List).map((json) => EventModel.fromJson(json)).toList();
  }
}
