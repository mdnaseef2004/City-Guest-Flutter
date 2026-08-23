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
    if (!superAdminEmails.contains(cleanEmail) && profile.role != 'sub_admin') {
      await updateProfile(userId, {'role': 'sub_admin'});
      return Profile(
        id: profile.id,
        name: profile.name,
        email: profile.email,
        role: 'sub_admin',
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

  // Update Profile
  static Future<void> updateProfile(String id, Map<String, dynamic> updates) async {
    await client.from('profiles').update(updates).eq('id', id);
  }

  // Delete Admin User Account from Database (Preserving Guest & Event Records)
  static Future<void> deleteUser(String userId) async {
    // 1. Unlink created_by in guest_visits and events to preserve all guest and event data
    try {
      await client.from('guest_visits').update({'created_by': null}).eq('created_by', userId);
    } catch (_) {}

    try {
      await client.from('events').update({'created_by': null}).eq('created_by', userId);
    } catch (_) {}

    // 2. Delete from auth.users & public.profiles using RPC or direct deletion
    try {
      await client.rpc('delete_user_by_admin', params: {'user_id': userId});
    } catch (_) {}

    try {
      await client.from('profiles').delete().eq('id', userId);
    } catch (_) {}
  }

  // Create New Sub Admin / Super Admin User Account
  static Future<void> createAdminUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // 1. Check if profile with email already exists in public.profiles
    try {
      final existingProfile = await client
          .from('profiles')
          .select('id')
          .eq('email', cleanEmail)
          .maybeSingle();

      if (existingProfile != null) {
        throw Exception('An admin account with email "$cleanEmail" already exists in database.');
      }
    } catch (e) {
      if (e.toString().contains('already exists')) rethrow;
    }

    final tempClient = SupabaseClient(
      AppConstants.supabaseUrl,
      AppConstants.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );

    String? userId;

    try {
      final response = await tempClient.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'name': name.trim(), 'role': role},
      );

      userId = response.user?.id;
    } on AuthException catch (_) {
      // If user is already registered in Supabase Auth, try signing in with provided password
      try {
        final signInRes = await tempClient.auth.signInWithPassword(
          email: cleanEmail,
          password: password,
        );
        userId = signInRes.user?.id;
      } catch (_) {
        throw Exception('The email "$cleanEmail" is already registered in Supabase Auth. Please try a different email address.');
      }
    } catch (e) {
      final errStr = e.toString().replaceAll('Exception:', '').trim();
      throw Exception(errStr);
    }

    // 2. Fallback: Check if database trigger handle_new_user created profile ID
    if (userId == null || userId.isEmpty) {
      try {
        final profCheck = await client
            .from('profiles')
            .select('id')
            .eq('email', cleanEmail)
            .maybeSingle();
        if (profCheck != null && profCheck['id'] != null) {
          userId = profCheck['id'].toString();
        }
      } catch (_) {}
    }

    // Strict validation: NEVER proceed to upsert if userId is null
    if (userId == null || userId.isEmpty) {
      throw Exception('The email "$cleanEmail" is already registered in Supabase. Please use a different email address.');
    }

    // 3. Insert or update profile in public.profiles table safely
    try {
      await client.from('profiles').upsert({
        'id': userId,
        'name': name.trim(),
        'email': cleanEmail,
        'role': role,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to save user profile: $e');
    }

    try {
      await tempClient.auth.signOut();
    } catch (_) {}
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
