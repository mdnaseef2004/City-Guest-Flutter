import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  Profile? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _profile != null;
  bool get isSuperAdmin => _profile?.isSuperAdmin ?? false;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    _checkInitialSession();
  }

  Future<void> _checkInitialSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        _profile = await SupabaseService.getProfile(user.id);
      }
    } catch (e) {
      _profile = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await SupabaseService.signIn(email, password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _profile = null;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await SupabaseService.signOut();
    _profile = null;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      _profile = await SupabaseService.getProfile(user.id);
      notifyListeners();
    }
  }

  Future<void> updateProfile({
    String? name,
    String? profilePicture,
    String? dateOfBirth,
    String? phoneNumber,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name.trim();
    if (profilePicture != null) updates['profile_picture'] = profilePicture.trim();
    if (dateOfBirth != null) updates['date_of_birth'] = dateOfBirth;
    if (phoneNumber != null) updates['phone_number'] = phoneNumber.trim();

    if (updates.isNotEmpty) {
      await SupabaseService.updateProfile(user.id, updates);
      await refreshProfile();
    }
  }
}
