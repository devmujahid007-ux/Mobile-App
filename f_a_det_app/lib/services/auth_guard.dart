import 'package:flutter/material.dart';

import 'auth_storage.dart';
import 'neuroscan_api.dart';

/// Ensures a valid JWT before showing a protected screen.
class AuthGuard {
  AuthGuard._();

  /// Returns `true` if the user may stay on this route.
  static Future<bool> redirectIfUnauthenticated(BuildContext context) async {
    final t = await AuthStorage.getToken();
    if (!context.mounted) return false;
    if (t == null || t.isEmpty) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      return false;
    }
    try {
      await NeuroscanApi.me();
      return true;
    } catch (_) {
      await AuthStorage.clearToken();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
      return false;
    }
  }
}
