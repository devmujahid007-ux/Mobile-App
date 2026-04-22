import 'package:flutter/material.dart';

import 'auth_storage.dart';

/// Ensures a valid JWT before showing a protected screen.
class AuthGuard {
  AuthGuard._();

  /// Returns `true` if the user may stay on this route.
  static Future<bool> redirectIfUnauthenticated(
    BuildContext context, {
    Set<String>? allowedRoles,
  }) async {
    final normalizedRoles = allowedRoles?.map((r) => r.toLowerCase()).toSet();
    final t = await AuthStorage.getToken();
    if (!context.mounted) return false;
    if (t == null || t.isEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      return false;
    }

    if (normalizedRoles != null && normalizedRoles.isNotEmpty) {
      final role = (await AuthStorage.getRole())?.toLowerCase();
      if (role == null || !normalizedRoles.contains(role)) {
        if (!context.mounted) return false;
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        return false;
      }
    }
    return true;
  }

  static Future<bool> canAccess({
    Set<String>? allowedRoles,
  }) async {
    final token = await AuthStorage.getToken();
    if (token == null || token.isEmpty) return false;
    final normalizedRoles = allowedRoles?.map((r) => r.toLowerCase()).toSet();
    if (normalizedRoles == null || normalizedRoles.isEmpty) return true;
    final role = (await AuthStorage.getRole())?.toLowerCase();
    return role != null && normalizedRoles.contains(role);
  }

  static Future<void> signOutAndRedirect(BuildContext context) async {
    await AuthStorage.clearToken();
    if (context.mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }
}
