import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Base URL for the NeuroScanAi FastAPI backend (`backend/main.py`).
///
/// Override at build/run time, e.g.:
/// `flutter run --dart-define=NEUROSCAN_API_URL=http://192.168.1.5:8000`
///
/// **Flutter Web (Chrome):** if you pass a LAN IP (`192.168.x.x`, `10.x`, etc.), it is
/// automatically rewritten to `http://127.0.0.1:<port>` so Chrome can reach an API on the
/// same PC (Private Network Access blocks `localhost` → LAN otherwise).
/// To force the LAN URL on web (API on another machine), use:
/// `--dart-define=NEUROSCAN_WEB_USE_LAN=true`
class NeuroscanApiConfig {
  NeuroscanApiConfig._();

  static const String _dartDefine =
      String.fromEnvironment('NEUROSCAN_API_URL', defaultValue: '');

  /// Set `true` only if the API runs on another device and you use Flutter **web**.
  static const bool _webUseLan =
      bool.fromEnvironment('NEUROSCAN_WEB_USE_LAN', defaultValue: false);

  /// Android emulator reaches the host via `10.0.2.2`. On a physical device,
  /// use `--dart-define=NEUROSCAN_API_URL=http://<PC_LAN_IP>:8000`.
  static String get baseUrl {
    final String raw;
    if (_dartDefine.isNotEmpty) {
      raw = _dartDefine;
    } else if (kIsWeb) {
      raw = 'http://127.0.0.1:8000';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      raw = 'http://10.0.2.2:8000';
    } else {
      raw = 'http://127.0.0.1:8000';
    }

    var url = raw.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return url;

    if (kIsWeb && !_webUseLan && _isPrivateLanHost(uri.host)) {
      url = uri.replace(host: '127.0.0.1').toString();
    }
    return url;
  }

  static bool _isPrivateLanHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1') return false;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }
}
