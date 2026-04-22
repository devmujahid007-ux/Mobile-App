import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kTokenKey = 'neuroscan_access_token';
const _kRoleKey = 'neuroscan_user_role';

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

  static String? roleFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = json.decode(decoded);
      if (map is Map && map['role'] != null) {
        final role = '${map['role']}'.toLowerCase().trim();
        return role.isEmpty ? null : role;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setRole(String role) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRoleKey, role.toLowerCase().trim());
  }

  static Future<void> setSession({
    required String token,
    String? role,
  }) async {
    final p = await SharedPreferences.getInstance();
    final resolvedRole = (role ?? roleFromToken(token) ?? '').toLowerCase().trim();
    if (resolvedRole.isNotEmpty) {
      await Future.wait([
        p.setString(_kTokenKey, token),
        p.setString(_kRoleKey, resolvedRole),
      ]);
    } else {
      await Future.wait([
        p.setString(_kTokenKey, token),
        p.remove(_kRoleKey),
      ]);
    }
  }

  static Future<String?> getRole() async {
    final p = await SharedPreferences.getInstance();
    final cached = p.getString(_kRoleKey);
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.toLowerCase().trim();
    }
    final token = p.getString(_kTokenKey);
    if (token == null || token.isEmpty) return null;
    final decoded = roleFromToken(token);
    if (decoded != null && decoded.isNotEmpty) {
      await p.setString(_kRoleKey, decoded);
      return decoded;
    }
    return null;
  }

  static Future<void> clearToken() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTokenKey);
    await p.remove(_kRoleKey);
  }
}
