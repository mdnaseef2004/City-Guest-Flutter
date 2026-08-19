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
    // 1. Unlink created_by in guests and events to preserve all guest and event data
    try {
      await client.from('guests').update({'created_by': null}).eq('created_by', userId);
    } catch (_) {}

    try {
      await client.from('events').update({'created_by': null}).eq('created_by', userId);
    } catch (_) {}

    // 2. Delete from auth.users & public.profiles using RPC or direct deletion
    try {
      await client.rpc('delete_user_by_admin', params: {'user_id': userId});
    } catch (_) {
      await client.from('profiles').delete().eq('id', userId);
    }
  }

  // Create New Sub Admin / Super Admin User Account
  static Future<void> createAdminUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // Check if email already exists in public profiles table
    final existingProfile = await client
        .from('profiles')
        .select('id')
        .eq('email', cleanEmail)
        .maybeSingle();

    if (existingProfile != null) {
      throw Exception('An admin account with email "$cleanEmail" already exists.');
    }

    // Use a separate SupabaseClient instance so active Super Admin session is not affected
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
        data: {'name': name, 'role': role},
      );

      if (response.user != null) {
        userId = response.user!.id;
      }
    } catch (e) {
      final errStr = e.toString();

      // If user was registered in auth.users during previous attempts, try logging in with tempClient
      try {
        final signInRes = await tempClient.auth.signInWithPassword(
          email: cleanEmail,
          password: password,
        );
        if (signInRes.user != null) {
          userId = signInRes.user!.id;
        }
      } catch (_) {
        if (errStr.contains('already registered') || errStr.contains('User already exists')) {
          throw Exception('An account with email "$cleanEmail" is already registered in Auth. Please try a different email or sign in.');
        }
        if (errStr.contains('Database error saving new user') || errStr.contains('unexpected_failure')) {
          // Check if profile was inserted despite trigger error
          try {
            final profCheck = await client
                .from('profiles')
                .select('id')
                .eq('email', cleanEmail)
                .maybeSingle();
            if (profCheck != null) {
              userId = profCheck['id'] as String;
            }
          } catch (_) {}

          if (userId == null) {
            throw Exception('Database Trigger Error in Supabase. Please run the SQL Fix in Supabase SQL Editor to drop the conflicting trigger.');
          }
        } else {
          rethrow;
        }
      }
    }

    if (userId == null) {
      throw Exception('Could not retrieve user ID from Auth. Please check email address and try again.');
    }

    // Safely update or insert profile in public.profiles table
    try {
      final existingProf = await client
          .from('profiles')
          .select('id')
          .or('id.eq.$userId,email.eq.$cleanEmail')
          .maybeSingle();

      if (existingProf != null) {
        await client.from('profiles').update({
          'name': name.trim(),
          'email': cleanEmail,
          'role': role,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existingProf['id']);
      } else {
        await client.from('profiles').insert({
          'id': userId,
          'name': name.trim(),
          'email': cleanEmail,
          'role': role,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {
      try {
        await client.from('profiles').update({
          'name': name.trim(),
          'email': cleanEmail,
          'role': role,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
      } catch (_) {}
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
