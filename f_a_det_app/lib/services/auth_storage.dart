import 'package:shared_preferences/shared_preferences.dart';

const _kTokenKey = 'neuroscan_access_token';

/// Stores the JWT returned by `POST /auth/login` (same as web `localStorage.token`).
class AuthStorage {
  AuthStorage._();

  static Future<String?> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kTokenKey);
  }

  static Future<void> setToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTokenKey, token);
  }

  static Future<void> clearToken() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTokenKey);
  }
}
