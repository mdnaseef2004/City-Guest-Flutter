import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/constants.dart';
import '../models/profile.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  }

  // Current Auth User
  static User? get currentUser => client.auth.currentUser;

  // Sign In with detailed error messages for wrong email vs wrong password
  static Future<Profile> signIn(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();

    try {
      final response = await client.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Authentication failed.');
      }

      // Check user active status
      final profile = await getProfile(response.user!.id);
      if (!profile.isActive) {
        await client.auth.signOut();
        throw Exception('Your account has been disabled. Please contact Super Admin.');
      }

      return profile;
    } on AuthException catch (_) {
      // Check if email exists in public profiles table
      try {
        final existingUser = await client
            .from('profiles')
            .select('id')
            .eq('email', cleanEmail)
            .maybeSingle();

        if (existingUser == null) {
          throw Exception('Invalid Username / Email Address');
        } else {
          throw Exception('Wrong Password');
        }
      } catch (e) {
        if (e.toString().contains('Invalid Username') || e.toString().contains('Wrong Password')) {
          rethrow;
        }
        throw Exception('Invalid Username / Email Address');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Sign Out
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  // Get Current User Profile
  static Future<Profile> getProfile(String userId) async {
    final data = await client
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();
    final profile = Profile.fromJson(data);

    final superAdminEmails = {
      'mdnaseef2004@gmail.com',
      'shaheenmohammed554@gmail.com',
      'mampadanmujeeb@gmail.com',
    };

    final cleanEmail = profile.email.trim().toLowerCase();
    
    // Automatically elevate whitelisted emails to super_admin if needed
    if (superAdminEmails.contains(cleanEmail) && profile.role != 'super_admin') {
      await updateProfile(userId, {'role': 'super_admin'});
      return Profile(
        id: profile.id,
        name: profile.name,
        email: profile.email,
        role: 'super_admin',
        isActive: profile.isActive,
        profilePicture: profile.profilePicture,
        dateOfBirth: profile.dateOfBirth,
        phoneNumber: profile.phoneNumber,
        createdAt: profile.createdAt,
      );
    }

    return profile;
  }

  // Get All Profiles (Users)
  static Future<List<Profile>> getUsers() async {
    final data = await client
        .from('profiles')
        .select('*')
        .order('created_at', ascending: true);
    return (data as List).map((json) => Profile.fromJson(json)).toList();
  }

  // Admin Supabase Client with Service Role Key for Admin Auth tasks
  static SupabaseClient get _adminClient => SupabaseClient(
        AppConstants.supabaseUrl,
        AppConstants.supabaseServiceKey,
      );

  // Update Profile
  static Future<void> updateProfile(String id, Map<String, dynamic> updates) async {
    await client.from('profiles').update(updates).eq('id', id);
  }

  // Delete Admin User Account from Database (Preserving Guest & Event Records)
  static Future<void> deleteUser(String userId) async {
    // 1. Unlink created_by & assignment references to preserve all guest, event, and task data
    try {
      await client.from('guest_visits').update({'created_by': null}).eq('created_by', userId);
    } catch (_) {}

    try {
      await client.from('events').update({'created_by': null}).eq('created_by', userId);
    } catch (_) {}

    try {
      await client.from('guest_assignments').update({'assigned_by': null}).eq('assigned_by', userId);
    } catch (_) {}

    // 2. Delete user from Supabase Auth using Service Role Admin API
    try {
      await _adminClient.auth.admin.deleteUser(userId);
    } catch (_) {}

    // 3. Delete profile from public.profiles table
    await client.from('profiles').delete().eq('id', userId);
  }

  // Create New Sub Admin / Super Admin User Account
  static Future<void> createAdminUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // 1. Create user in Supabase Auth via Service Role Admin API with email confirmed
    final UserResponse userRes = await _adminClient.auth.admin.createUserWithEmail(
      AdminUserAttributes(
        email: cleanEmail,
        password: password,
        emailConfirm: true,
        userMetadata: {'name': name.trim(), 'role': role},
      ),
    );

    final newUserId = userRes.user?.id;
    if (newUserId == null || newUserId.isEmpty) {
      throw Exception('Failed to create user in Supabase Auth.');
    }

    // 2. Upsert profile in public.profiles table to eliminate profiles_pkey duplicate constraint errors
    try {
      await client.from('profiles').upsert({
        'id': newUserId,
        'name': name.trim(),
        'email': cleanEmail,
        'role': role,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('User created in Auth but profile save failed: $e');
    }
  }

  // Upload Profile Picture to Supabase Storage
  static Future<String> uploadProfilePicture(Uint8List bytes, String userId) async {
    final fileName = 'avatars/$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage.from('guest-pdfs').uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return client.storage.from('guest-pdfs').getPublicUrl(fileName);
  }
}
