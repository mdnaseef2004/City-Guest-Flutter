import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/guest_visit.dart';
import '../models/visited_place.dart';
import 'supabase_service.dart';

class GuestService {
  static final SupabaseClient _client = SupabaseService.client;

  // Duplicate Check: Check if same guest name entered today by current user
  static Future<bool> checkDuplicateGuest(String guestName) async {
    final user = SupabaseService.currentUser;
    if (user == null) return false;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final response = await _client
        .from('guest_visits')
        .select('id')
        .eq('created_by', user.id)
        .ilike('guest_name', guestName.trim())
        .gte('created_at', '${today}T00:00:00.000Z')
        .lte('created_at', '${today}T23:59:59.999Z');

    return (response as List).isNotEmpty;
  }

  // Upload Guest Photo to Supabase Storage
  static Future<String?> uploadGuestPhoto(File imageFile) async {
    try {
      final fileExt = imageFile.path.split('.').last;
      final fileName = 'photos/guest-photo-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      
      await _client.storage.from('guest-pdfs').upload(fileName, imageFile);
      return _client.storage.from('guest-pdfs').getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  // Add New Guest Visit with Visited Places
  static Future<GuestVisit> addGuest({
    required String guestName,
    required String phoneNumber,
    String? occupation,
    String? photoUrl,
    required String place,
    required String district,
    String? state,
    String? country,
    bool isInternational = false,
    required String purpose,
    double donationAmount = 0.0,
    String? receiptNo,
    String? pickedFrom,
    String? pickedDate,
    String? pickedTime,
    String? guestReturned,
    String? returnDate,
    String? returnTime,
    String? handledBy,
    String? remarks,
    List<VisitedPlace> visitedPlaces = const [],
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Insert guest_visits
    final visitData = await _client.from('guest_visits').insert({
      'guest_name': guestName.trim(),
      'phone_number': phoneNumber.trim(),
      'occupation': occupation?.trim(),
      'photo_url': photoUrl,
      'place': place.trim(),
      'district': district.trim(),
      'state': isInternational ? null : state,
      'country': isInternational ? country : null,
      'is_international': isInternational,
      'purpose': purpose.trim(),
      'donation_amount': donationAmount,
      'receipt_no': receiptNo?.trim(),
      'picked_from': pickedFrom?.trim(),
      'picked_date': pickedDate,
      'picked_time': pickedTime,
      'guest_returned': guestReturned,
      'return_date': returnDate,
      'return_time': returnTime,
      'handled_by': handledBy?.trim(),
      'remarks': remarks?.trim(),
      'created_by': user.id,
    }).select().single();

    final String visitId = visitData['id'].toString();

    // Batch insert visited_places if provided
    if (visitedPlaces.isNotEmpty) {
      final placesToInsert = visitedPlaces
          .where((vp) => vp.visitedPlace.trim().isNotEmpty)
          .map((vp) => {
                'guest_visit_id': visitId,
                'visited_place': vp.visitedPlace.trim(),
                'visit_date': vp.visitDate,
                'time_in': vp.timeIn,
                'time_out': vp.timeOut,
              })
          .toList();

      if (placesToInsert.isNotEmpty) {
        await _client.from('visited_places').insert(placesToInsert);
      }
    }

    return GuestVisit.fromJson(visitData);
  }

  // Update Guest Visit
  static Future<void> updateGuest(String id, Map<String, dynamic> updates, List<VisitedPlace> visitedPlaces) async {
    await _client.from('guest_visits').update(updates).eq('id', id);

    // Replace visited places
    await _client.from('visited_places').delete().eq('guest_visit_id', id);
    if (visitedPlaces.isNotEmpty) {
      final placesToInsert = visitedPlaces
          .where((vp) => vp.visitedPlace.trim().isNotEmpty)
          .map((vp) => {
                'guest_visit_id': id,
                'visited_place': vp.visitedPlace.trim(),
                'visit_date': vp.visitDate,
                'time_in': vp.timeIn,
                'time_out': vp.timeOut,
              })
          .toList();

      if (placesToInsert.isNotEmpty) {
        await _client.from('visited_places').insert(placesToInsert);
      }
    }
  }

  // Bulk Insert Guests from CSV / Excel Import
  static Future<void> bulkAddGuests(List<Map<String, dynamic>> rows) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final visitsToInsert = rows.map((r) => {
      'guest_name': r['guest_name'] ?? 'Unknown',
      'phone_number': r['phone_number']?.toString() ?? '',
      'occupation': r['occupation'],
      'place': r['place'] ?? 'Unknown',
      'district': r['district'] ?? 'Unknown',
      'state': r['state'],
      'country': r['country'],
      'is_international': r['country'] != null && r['country'].toString().isNotEmpty,
      'purpose': r['purpose'] ?? 'Visit',
      'donation_amount': double.tryParse(r['donation_amount']?.toString() ?? '0') ?? 0.0,
      'receipt_no': r['receipt_no'],
      'picked_from': r['picked_from'] ?? '',
      'picked_date': r['picked_date'],
      'picked_time': r['picked_time'],
      'guest_returned': r['guest_returned'],
      'return_date': r['return_date'],
      'return_time': r['return_time'],
      'handled_by': r['handled_by'] ?? '',
      'remarks': r['remarks'] ?? '',
      'created_by': user.id,
      'created_at': r['visited_date'] ?? DateTime.now().toIso8601String(),
    }).toList();

    await _client.from('guest_visits').insert(visitsToInsert);
  }

  // Get Today's Guest Visits List
  static Future<List<GuestVisit>> getTodayGuests(bool isSuperAdmin) async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    dynamic query = _client.from('guest_visits').select('*, profiles!guest_visits_created_by_fkey(name), visited_places(*)');

    if (!isSuperAdmin) {
      query = query.eq('created_by', user.id);
    }

    final data = await query
        .gte('created_at', '${todayStr}T00:00:00.000Z')
        .lte('created_at', '${todayStr}T23:59:59.999Z')
        .order('created_at', ascending: false);

    return (data as List).map((json) => GuestVisit.fromJson(json)).toList();
  }

  // Get All Guests For Reports
  static Future<List<GuestVisit>> getAllGuestsForReports({
    String? startDate,
    String? endDate,
    String? createdBy,
    String? handledBy,
    bool onlyDonations = false,
    bool isSuperAdmin = false,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];

    dynamic query = _client.from('guest_visits').select('*, profiles!guest_visits_created_by_fkey(name), visited_places(*)');

    if (!isSuperAdmin) {
      query = query.eq('created_by', user.id);
    }
    if (createdBy != null && createdBy.isNotEmpty) query = query.eq('created_by', createdBy);
    if (handledBy != null && handledBy.isNotEmpty) query = query.eq('handled_by', handledBy);
    if (startDate != null && startDate.isNotEmpty) query = query.gte('created_at', '${startDate}T00:00:00.000Z');
    if (endDate != null && endDate.isNotEmpty) query = query.lte('created_at', '${endDate}T23:59:59.999Z');
    if (onlyDonations) query = query.gt('donation_amount', 0);

    final data = await query.order('created_at', ascending: false);
    return (data as List).map((json) => GuestVisit.fromJson(json)).toList();
  }

  // Fetch Guest Records with Filters & Pagination
  static Future<Map<String, dynamic>> getGuests({
    String? search,
    String? place,
    String? district,
    String? state,
    String? country,
    String? purpose,
    String? createdBy,
    String? handledBy,
    String? startDate,
    String? endDate,
    int page = 1,
    int perPage = 20,
    bool isSuperAdmin = false,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('User not authenticated');

    dynamic query = _client.from('guest_visits').select('*, profiles!guest_visits_created_by_fkey(name), visited_places(*)');

    if (!isSuperAdmin) {
      query = query.eq('created_by', user.id);
    }
    if (createdBy != null && createdBy.isNotEmpty) query = query.eq('created_by', createdBy);
    if (handledBy != null && handledBy.isNotEmpty) query = query.eq('handled_by', handledBy);
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('guest_name', '%${search.trim()}%');
    }
    if (place != null && place.isNotEmpty) query = query.eq('place', place);
    if (district != null && district.isNotEmpty) query = query.eq('district', district);
    if (state != null && state.isNotEmpty) query = query.eq('state', state);
    if (country != null && country.isNotEmpty) query = query.eq('country', country);
    if (purpose != null && purpose.isNotEmpty) query = query.eq('purpose', purpose);
    if (startDate != null && startDate.isNotEmpty) query = query.gte('created_at', '${startDate}T00:00:00.000Z');
    if (endDate != null && endDate.isNotEmpty) query = query.lte('created_at', '${endDate}T23:59:59.999Z');

    final fromIndex = (page - 1) * perPage;
    final toIndex = page * perPage - 1;

    final response = await query
        .order('created_at', ascending: false)
        .range(fromIndex, toIndex)
        .count(CountOption.exact);

    final List<GuestVisit> guests = (response.data as List)
        .map((json) => GuestVisit.fromJson(json))
        .toList();

    return {
      'data': guests,
      'total': response.count ?? 0,
    };
  }

  // Delete Guest Record
  static Future<void> deleteGuest(String id) async {
    await _client.from('guest_visits').delete().eq('id', id);
  }

  // Unique Dropdown Options
  static Future<List<String>> getUniquePlaces(bool isSuperAdmin) async {
    final user = SupabaseService.currentUser;
    dynamic query = _client.from('guest_visits').select('place');
    if (!isSuperAdmin && user != null) query = query.eq('created_by', user.id);
    final data = await query;
    final set = (data as List).map((e) => e['place']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
    final list = set.toList()..sort();
    return list;
  }

  static Future<List<String>> getUniquePurposes(bool isSuperAdmin) async {
    final user = SupabaseService.currentUser;
    dynamic query = _client.from('guest_visits').select('purpose');
    if (!isSuperAdmin && user != null) query = query.eq('created_by', user.id);
    final data = await query;
    final set = (data as List).map((e) => e['purpose']?.toString() ?? '').where((s) => s.isNotEmpty).toSet();
    final list = set.toList()..sort();
    return list;
  }

  // Complete Dashboard Stats matching 100% of website data including Profile Pictures (Optimized Parallel Execution)
  static Future<Map<String, dynamic>> getDashboardStats(bool isSuperAdmin) async {
    final user = SupabaseService.currentUser;
    if (user == null) return {};

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';

    // 1. Prepare queries for parallel execution
    dynamic countBuilder = _client.from('guest_visits').select('id');
    if (!isSuperAdmin) countBuilder = countBuilder.eq('created_by', user.id);

    dynamic todayBuilder = _client.from('guest_visits').select('id').gte('created_at', '${todayStr}T00:00:00.000Z');
    if (!isSuperAdmin) todayBuilder = todayBuilder.eq('created_by', user.id);

    dynamic monthBuilder = _client.from('guest_visits').select('donation_amount').gte('created_at', '${monthStr}T00:00:00.000Z');
    if (!isSuperAdmin) monthBuilder = monthBuilder.eq('created_by', user.id);

    // 2. Execute base queries concurrently in parallel with Future.wait
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      countBuilder.count(CountOption.exact),
      todayBuilder.count(CountOption.exact),
      monthBuilder,
      _client.from('profiles').select('*'),
      _client.from('events').select('*'),
    ]);

    final PostgrestResponse countRes = results[0] as PostgrestResponse;
    final PostgrestResponse todayRes = results[1] as PostgrestResponse;
    final List monthList = results[2] as List;
    final List usersList = (results[3] as List).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> eventsList = (results[4] as List).cast<Map<String, dynamic>>();

    // 3. Range-page through 100% of rows to bypass Supabase 1000 row REST limit
    final List<Map<String, dynamic>> allRows = [];
    int fromIndex = 0;
    const int pageSize = 1000;
    while (true) {
      dynamic pageBuilder = _client
          .from('guest_visits')
          .select('id, guest_name, place, purpose, donation_amount, created_at, created_by, photo_url, handled_by, remarks')
          .range(fromIndex, fromIndex + pageSize - 1);
      if (!isSuperAdmin) pageBuilder = pageBuilder.eq('created_by', user.id);
      final List<Map<String, dynamic>> pageData = (await pageBuilder as List).cast<Map<String, dynamic>>();
      if (pageData.isEmpty) break;
      allRows.addAll(pageData);
      if (pageData.length < pageSize) break;
      fromIndex += pageSize;
    }

    final double monthlyDonations = monthList.fold(0.0, (sum, x) => sum + ((x['donation_amount'] ?? 0) as num).toDouble());

    // 3. Process Events Data for Event Graph
    final Map<String, int> eventPlaceMap = {};
    int totalEventMembers = 0;
    for (final ev in eventsList) {
      final String place = ev['event_place']?.toString() ?? ev['event_name']?.toString() ?? 'Main Campus';
      final int count = ((ev['members_count'] ?? 1) as num).toInt();
      totalEventMembers += count;
      eventPlaceMap[place] = (eventPlaceMap[place] ?? 0) + (count > 0 ? count : 1);
    }

    final List<Map<String, dynamic>> eventsGraphData = eventPlaceMap.entries
        .map((e) => {'label': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    // 4. Calculate total donations sum across rows
    double totalDonations = 0.0;
    for (final r in allRows) {
      totalDonations += ((r['donation_amount'] ?? 0) as num).toDouble();
    }

    // 7. Guests by Place Breakdown
    final Map<String, int> placeMap = {};
    for (final r in allRows) {
      final String place = r['place']?.toString() ?? '';
      if (place.isNotEmpty) {
        placeMap[place] = (placeMap[place] ?? 0) + 1;
      }
    }
    final List<Map<String, dynamic>> guestsByPlace = placeMap.entries
        .map((e) => {'place': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    final List<Map<String, dynamic>> topPlaces = guestsByPlace.take(10).toList();

    // 8. Guests by Purpose Breakdown
    final Map<String, int> purposeMap = {};
    for (final r in allRows) {
      final String purpose = r['purpose']?.toString() ?? '';
      if (purpose.isNotEmpty) {
        purposeMap[purpose] = (purposeMap[purpose] ?? 0) + 1;
      }
    }
    final List<Map<String, dynamic>> guestsByPurpose = purposeMap.entries
        .map((e) => {'purpose': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    // 9. Recent Guest Photos (with photo_url)
    final List<Map<String, dynamic>> recentPhotos = allRows
        .where((r) => r['photo_url'] != null && r['photo_url'].toString().trim().isNotEmpty)
        .toList()
      ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));

    // 10. Admin Performance (subAdminPerf & superAdminPerf with profile_picture & lastEntry date)
    List<Map<String, dynamic>> subAdminPerf = [];
    List<Map<String, dynamic>> superAdminPerf = [];

    for (final u in usersList) {
      final String uid = u['id'].toString();
      final String name = u['name'] ?? 'User';
      final String role = u['role'] ?? 'sub_admin';
      final String? profilePic = u['profile_picture']?.toString();

      final userVisits = allRows.where((r) => r['created_by'] == uid).toList();
      userVisits.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));

      final double userDonationsSum = userVisits.fold(0.0, (s, r) => s + ((r['donation_amount'] ?? 0) as num).toDouble());
      final String? lastEntryDate = userVisits.isNotEmpty ? userVisits.first['created_at']?.toString() : null;

      final perfItem = {
        'id': uid,
        'name': name,
        'role': role,
        'profile_picture': profilePic,
        'totalEntries': userVisits.length,
        'totalDonations': userDonationsSum,
        'lastEntry': lastEntryDate,
      };

      if (role == 'super_admin') {
        superAdminPerf.add(perfItem);
      } else {
        subAdminPerf.add(perfItem);
      }
    }

    subAdminPerf.sort((a, b) => (b['totalEntries'] as int).compareTo(a['totalEntries'] as int));
    superAdminPerf.sort((a, b) => (b['totalEntries'] as int).compareTo(a['totalEntries'] as int));

    return {
      'totalGuests': countRes.count,
      'todayGuests': todayRes.count,
      'totalDonations': totalDonations,
      'monthlyDonations': monthlyDonations,
      'monthlyGuestsCount': monthList.length,
      'guestsByPlace': topPlaces,
      'guestsByPurpose': guestsByPurpose,
      'recentPhotos': recentPhotos.take(20).toList(),
      'subAdminPerf': subAdminPerf,
      'superAdminPerf': superAdminPerf,
      'rawGuests': allRows,
      'allUsers': usersList,
      'totalEvents': eventsList.length,
      'totalEventMembers': totalEventMembers,
      'eventsGraphData': eventsGraphData,
      'rawEvents': eventsList,
    };
  }
}
