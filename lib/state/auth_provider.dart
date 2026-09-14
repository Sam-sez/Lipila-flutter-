import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/users_api.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  static const _prefsKey = 'lipila_user_id';
  final UsersApi _usersApi = UsersApi();

  LipilaUser? user;
  bool loading = true;

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);
    if (savedId != null) {
      try {
        user = await _usersApi.get(savedId);
      } catch (_) {
        await prefs.remove(_prefsKey);
      }
    }
    loading = false;
    notifyListeners();
  }

  /// Creates a brand-new account. Only call this after confirming (via
  /// getByNumber) that the number isn't already registered.
  Future<void> createAccount({
    required String mobileNumber,
    required String legalName,
    bool isAgent = false,
  }) async {
    final created = await _usersApi.create(
      mobileNumber: mobileNumber,
      legalName: legalName,
      isAgent: isAgent,
      merchantCategory: isAgent ? 'agent' : null,
    );
    await _persistAndSet(created);
  }

  /// Resumes an existing account by number alone — no password in this
  /// prototype, so this IS the "sign in" flow.
  Future<bool> loginExisting(String mobileNumber) async {
    final existing = await _usersApi.getByNumber(mobileNumber);
    if (existing == null) return false;
    await _persistAndSet(existing);
    return true;
  }

  Future<void> _persistAndSet(LipilaUser u) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, u.id);
    user = u;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    if (user == null) return;
    user = await _usersApi.get(user!.id);
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    user = null;
    notifyListeners();
  }
}
