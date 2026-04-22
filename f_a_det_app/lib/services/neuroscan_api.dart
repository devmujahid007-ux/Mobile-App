import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_storage.dart';
import 'neuroscan_api_config.dart';
import 'patient_zip_path_size_stub.dart'
    if (dart.library.io) 'patient_zip_path_size_io.dart' as patient_zip_path;

class NeuroscanApiException implements Exception {
  NeuroscanApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// FastAPI client aligned with
/// `NeuroScanAi/frontend/.../src/api.js` and `backend` routers.
class NeuroscanApi {
  NeuroscanApi._();
  static String? _activeBaseUrl;

  /// Login/register wait for DB; cold MySQL on Windows can exceed a few seconds.
  static const Duration _authRequestTimeout = Duration(seconds: 45);

  /// BraTS upload + sliding-window inference + PDF can take many minutes on CPU.
  static const Duration _segmentationMultipartTimeout = Duration(minutes: 25);

  static Uri _uriForBase(String base, String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  /// On Flutter Web, same-machine API is often reachable only via `127.0.0.1` while the app
  /// is configured with a LAN IP — used for auth racing and as a secondary base in fallbacks.
  static String? _fallbackBaseUrl(String primaryBase) {
    if (!kIsWeb) return null;
    final uri = Uri.tryParse(primaryBase);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.host == '127.0.0.1' || uri.host == 'localhost') return null;
    final parts = uri.host.split('.');
    if (parts.length != 4) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return null;
    final isPrivateLan = a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
    if (!isPrivateLan) return null;
    return uri.replace(host: '127.0.0.1').toString();
  }

  /// Bases to race for login/register on web (127.0.0.1 vs localhost, LAN vs loopback).
  static List<String> _webAuthRaceBases(String primary) {
    final out = <String>[];
    void add(String? b) {
      if (b == null || b.isEmpty) return;
      final t = b.trim();
      if (!out.contains(t)) out.add(t);
    }

    add(primary);
    final primaryUri = Uri.tryParse(primary);
    if (primaryUri != null) {
      if (primaryUri.host == '127.0.0.1') {
        add(primaryUri.replace(host: 'localhost').toString());
      } else if (primaryUri.host == 'localhost') {
        add(primaryUri.replace(host: '127.0.0.1').toString());
      }
    }
    final alt = _fallbackBaseUrl(primary);
    add(alt);
    if (alt != null) {
      final u = Uri.tryParse(alt);
      if (u != null && u.host == '127.0.0.1') {
        add(u.replace(host: 'localhost').toString());
      }
    }
    return out;
  }

  static Future<T> _withConnectivityFallback<T>(
    Future<T> Function(String base) action,
  ) async {
    final primaryBase = NeuroscanApiConfig.baseUrl;
    final fallbackBase = _fallbackBaseUrl(primaryBase);

    final tryOrder = <String>[];
    void addBase(String b) {
      final t = b.trim();
      if (t.isEmpty) return;
      if (!tryOrder.contains(t)) tryOrder.add(t);
    }

    final active = _activeBaseUrl;
    // Flutter web (same PC): `primaryBase` is already rewritten to 127.0.0.1. Try it before a
    // stale `_activeBaseUrl` from a LAN IP — avoids a failing first hop and bogus error banners.
    if (kIsWeb && !NeuroscanApiConfig.webUseLan) {
      addBase(primaryBase);
      if (fallbackBase != null) {
        addBase(fallbackBase);
        final u = Uri.tryParse(fallbackBase);
        if (u != null && u.host == '127.0.0.1') {
          addBase(u.replace(host: 'localhost').toString());
        }
      }
      if (active != null && active.isNotEmpty) addBase(active);
    } else {
      if (active != null && active.isNotEmpty) addBase(active);
      addBase(primaryBase);
      if (fallbackBase != null) {
        addBase(fallbackBase);
        final u = Uri.tryParse(fallbackBase);
        if (u != null && u.host == '127.0.0.1') {
          addBase(u.replace(host: 'localhost').toString());
        }
      }
    }

    Object? lastConnectivityError;
    for (final base in tryOrder) {
      try {
        final out = await action(base);
        _activeBaseUrl = base;
        return out;
      } catch (e) {
        if (!_isConnectivityFailure(e)) rethrow;
        lastConnectivityError = e;
      }
    }
    throw _connectionFailed(
      lastConnectivityError ?? 'unknown',
      base: primaryBase,
    );
  }

  /// Login/register: on web, request LAN and localhost in parallel so the first success wins
  /// (avoids waiting twice when the browser only reaches one host).
  static Future<http.Response> _postAuthRace(String path, Map<String, dynamic> body) async {
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final primary = NeuroscanApiConfig.baseUrl;
    final bases = kIsWeb ? _webAuthRaceBases(primary) : <String>[primary];

    if (bases.length == 1) {
      final res = await http
          .post(
            _uriForBase(bases.single, path),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(_authRequestTimeout);
      _activeBaseUrl = bases.single;
      return res;
    }

    final completer = Completer<http.Response>();
    var settled = false;
    var failureCount = 0;

    for (final base in bases) {
      http
          .post(
            _uriForBase(base, path),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(_authRequestTimeout)
          .then((http.Response res) {
            if (settled) return;
            settled = true;
            _activeBaseUrl = base;
            if (!completer.isCompleted) completer.complete(res);
          })
          .catchError((Object e, StackTrace _) {
            if (settled) return;
            failureCount++;
            if (failureCount >= bases.length && !completer.isCompleted) {
              if (_isConnectivityFailure(e)) {
                completer.completeError(_connectionFailed(e, base: primary));
              } else {
                completer.completeError(e);
              }
            }
          });
    }

    return completer.future;
  }

  static String absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return resolveMediaUrl(path);
    final base = _activeBaseUrl ?? NeuroscanApiConfig.baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  /// `/predict` returns absolute URLs with `127.0.0.1`; rewrite for emulator/LAN.
  static String resolveMediaUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    if (parsed.host == '127.0.0.1' || parsed.host == 'localhost') {
      final b = Uri.parse(_activeBaseUrl ?? NeuroscanApiConfig.baseUrl);
      return b.replace(path: parsed.path, query: parsed.query).toString();
    }
    return url;
  }

  static String? parseFastApiDetail(dynamic body) {
    if (body is! Map<String, dynamic>) return null;
    final d = body['detail'];
    if (d == null) return null;
    if (d is String) return d;
    if (d is List) {
      return d
          .map((e) {
            if (e is Map && e['msg'] != null) return '${e['msg']}';
            return '$e';
          })
          .where((s) => s.isNotEmpty)
          .join(' ');
    }
    if (d is Map && d['msg'] != null) return '${d['msg']}';
    try {
      return json.encode(d);
    } catch (_) {
      return '$d';
    }
  }

  static Future<Map<String, String>> _headersJson({bool requireAuth = false}) async {
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final t = await AuthStorage.getToken();
    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    } else if (requireAuth) {
      throw NeuroscanApiException('Not signed in');
    }
    return h;
  }

  static Future<Map<String, String>> _headersAuthMultipart() async {
    final t = await AuthStorage.getToken();
    if (t == null || t.isEmpty) throw NeuroscanApiException('Not signed in');
    return {'Authorization': 'Bearer $t'};
  }

  static String _messageFromResponse(http.Response res) {
    try {
      final m = json.decode(res.body);
      if (m is Map<String, dynamic>) {
        final d = parseFastApiDetail(m);
        if (d != null && d.isNotEmpty) return d;
        final err = m['error'];
        if (err != null) return '$err';
      }
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }

  /// Browser / mobile "no route to host" style failures (never an HTTP body).
  static NeuroscanApiException _connectionFailed(Object error, {String? base}) {
    final targetBase = base ?? NeuroscanApiConfig.baseUrl;
    return NeuroscanApiException(
      'Cannot reach the API at $targetBase\n\n'
      '• If the API runs on **this same PC** and you use Flutter **Web (Chrome)**:\n'
      '  flutter run -d chrome --dart-define=NEUROSCAN_API_URL=http://127.0.0.1:8000\n'
      '  (LAN IPs like 192.168.x.x are rewritten to 127.0.0.1 on web unless you set '
      'NEUROSCAN_WEB_USE_LAN=true for an API on *another* machine.)\n\n'
      '• If the API runs on **another machine** (e.g. 192.168.x.x): that PC must run\n'
      '  uvicorn main:app --host 0.0.0.0 --port 8000 and allow inbound TCP 8000 in its firewall.\n'
      '  On **this** PC, open $targetBase/docs in Chrome — if it fails, fix the network first.\n\n'
      '• Use latest backend from this repo (Access-Control-Allow-Private-Network for Chrome).\n\n'
      '• For phones / desktop app, LAN URL is fine: --dart-define=NEUROSCAN_API_URL=http://<host>:8000',
    );
  }

  static bool _isConnectivityFailure(Object e) {
    // Request timeouts (slow inference) must not be treated as "API unreachable"
    // or every base URL is retried and the user sees a misleading connectivity banner.
    if (e is TimeoutException) return false;
    final s = e.toString().toLowerCase();
    return s.contains('failed to fetch') ||
        s.contains('clientexception') ||
        s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('network is unreachable') ||
        s.contains('host lookup failed') ||
        s.contains('failed host lookup') ||
        s.contains('network error');
  }

  static Never _throwSegmentationTimedOut(String label) {
    throw NeuroscanApiException(
      '$label timed out after ${_segmentationMultipartTimeout.inMinutes} minutes. '
      'BraTS inference and PDF steps are heavy on CPU — keep the app open and try again, '
      'or run the API on hardware with GPU. Confirm the API is running (e.g. '
      'http://127.0.0.1:8000/docs).',
    );
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await _postAuthRace('/auth/login', {
        'email': email,
        'password': password,
      });
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw NeuroscanApiException(_messageFromResponse(res));
      }
      try {
        return json.decode(res.body) as Map<String, dynamic>;
      } on FormatException {
        throw NeuroscanApiException(
          'Invalid response from server. Expected JSON from ${NeuroscanApiConfig.baseUrl} — '
          'check NEUROSCAN_API_URL /docs matches this app.',
        );
      }
    } on NeuroscanApiException {
      rethrow;
    } on TimeoutException {
      throw NeuroscanApiException(
        'Login timed out after ${_authRequestTimeout.inSeconds}s. '
        'Check MySQL is running and backend/.env credentials, then open '
        '${NeuroscanApiConfig.baseUrl}/docs in a browser.',
      );
    } catch (e) {
      if (_isConnectivityFailure(e)) throw _connectionFailed(e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String role,
    String? name,
    int? age,
    String? phone,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'role': role,
      if (name != null) 'name': name,
      if (age != null) 'age': age,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    };
    try {
      final res = await _postAuthRace('/auth/register', body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw NeuroscanApiException(_messageFromResponse(res));
      }
      try {
        return json.decode(res.body) as Map<String, dynamic>;
      } on FormatException {
        throw NeuroscanApiException(
          'Invalid response from server at ${NeuroscanApiConfig.baseUrl}.',
        );
      }
    } on NeuroscanApiException {
      rethrow;
    } on TimeoutException {
      throw NeuroscanApiException(
        'Register timed out after ${_authRequestTimeout.inSeconds}s. '
        'Check MySQL and API at ${NeuroscanApiConfig.baseUrl}/docs.',
      );
    } catch (e) {
      if (_isConnectivityFailure(e)) throw _connectionFailed(e);
      rethrow;
    }
  }

  /// Process + MySQL check (GET /health). Use on login/register screens to surface setup issues early.
  static Future<Map<String, dynamic>> fetchHealth() async {
    final res = await _withConnectivityFallback(
      (base) => http.get(
        _uriForBase(base, '/health'),
        headers: const {'Accept': 'application/json'},
      ),
    );
    if (res.statusCode == 503) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    try {
      return json.decode(res.body) as Map<String, dynamic>;
    } on FormatException {
      throw NeuroscanApiException(
        'Unexpected /health response. Is ${NeuroscanApiConfig.baseUrl} the NeuroScan API?',
      );
    }
  }

  /// Public contact form endpoint (`POST /api/contact`).
  static Future<Map<String, dynamic>> sendContactMessage({
    required String name,
    required String email,
    String? subject,
    required String message,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'subject': (subject ?? '').trim(),
      'message': message.trim(),
    };
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/api/contact'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> me() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/auth/me'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getRecentAnalyses({
    int limit = 6,
    bool requireAuth = false,
  }) async {
    final headers = await _headersJson(requireAuth: requireAuth);
    final res = await _withConnectivityFallback(
      (base) => http.get(
        _uriForBase(base, '/api/analyses/recent').replace(
          queryParameters: {'limit': '$limit'},
        ),
        headers: headers,
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getAnalysis(int reportId) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/api/analyses/$reportId'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> listDoctors() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/api/patients/doctors'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  /// Web parity: `POST /api/patients/doctors`.
  static Future<Map<String, dynamic>> createDoctor({
    required String name,
    required String email,
    String? phone,
    required String password,
  }) async {
    final headers = await _headersJson(requireAuth: true);
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    };
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/api/patients/doctors'),
        headers: headers,
        body: json.encode(body),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Web parity: `DELETE /api/patients/doctors/{doctorId}`.
  static Future<Map<String, dynamic>> deleteDoctor(int doctorId) async {
    if (doctorId <= 0) throw NeuroscanApiException('Invalid doctor id');
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.delete(_uriForBase(base, '/api/patients/doctors/$doctorId'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// `GET /api/patients/` — patient directory for assigning scans/reports (doctor/admin).
  static Future<List<dynamic>> listPatients() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/api/patients/'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  /// Web parity: `POST /api/patients/`.
  static Future<Map<String, dynamic>> createPatient({
    required String name,
    required String email,
    String? phone,
    int? age,
    required String password,
  }) async {
    final headers = await _headersJson(requireAuth: true);
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (age != null) 'age': age,
    };
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/api/patients/'),
        headers: headers,
        body: json.encode(body),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Web parity: `DELETE /api/patients/{patientId}`.
  static Future<Map<String, dynamic>> deletePatient(int patientId) async {
    if (patientId <= 0) throw NeuroscanApiException('Invalid patient id');
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.delete(_uriForBase(base, '/api/patients/$patientId'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getPatientScans() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/mri/patient-scans'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  /// Patient request deletion (tumor/alzheimer): `DELETE /mri/patient-scans/{scanId}`.
  static Future<Map<String, dynamic>> deletePatientScan(int scanId) async {
    if (scanId <= 0) throw NeuroscanApiException('Invalid scan id');
    final headers = await _headersJson(requireAuth: true);
    var res = await _withConnectivityFallback(
      (base) => http.delete(_uriForBase(base, '/mri/patient-scans/$scanId'), headers: headers),
    );
    if (res.statusCode >= 400) {
      final msg = _messageFromResponse(res).toLowerCase();
      final looksLikeLegacyTumorOnly =
          msg.contains('tumor') && (msg.contains('only') || msg.contains('appl'));
      if (looksLikeLegacyTumorOnly || res.statusCode == 404 || res.statusCode == 405) {
        res = await _withConnectivityFallback(
          (base) => http.delete(_uriForBase(base, '/mri/patient-scans/$scanId/delete'), headers: headers),
        );
      }
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getPatientReports() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/api/analyses/patient-reports'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  /// Web-parity endpoint: `GET /reports` (doctor/patient/admin scoped).
  static Future<List<dynamic>> listReports() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/reports'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  /// Build URL for `/reports/{id}` so UI can open/download PDF.
  static Future<String> reportPdfOpenUrl(
    int reportId, {
    bool download = false,
    int? cacheBust,
  }) async {
    if (reportId <= 0) throw NeuroscanApiException('Invalid report id');
    final token = await AuthStorage.getToken();
    final query = <String, String>{};
    if (download) query['download'] = 'true';
    if (cacheBust != null) query['v'] = '$cacheBust';
    if (token != null && token.isNotEmpty) {
      query['access_token'] = token;
    }
    final base = _activeBaseUrl ?? NeuroscanApiConfig.baseUrl;
    final uri = _uriForBase(base, '/reports/$reportId').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    return uri.toString();
  }

  static Future<List<dynamic>> getDoctorRequests() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/mri/doctor-requests'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/api/stats/summary'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Admin / superadmin clinic overview (`GET /api/stats/admin-summary`).
  static Future<Map<String, dynamic>> getAdminSummary() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/api/stats/admin-summary'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// BraTS / PyTorch diagnostics (`GET /api/analyses/model-status`).
  static Future<Map<String, dynamic>> getModelStatus() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/api/analyses/model-status'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> listUsers() async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/users/'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  /// Public BraTS-style segmentation (`POST /predict`) — no JWT.
  static Future<Map<String, dynamic>> predictTumorSegmentation(
    Map<String, PlatformFile> filesByModality,
  ) async {
    for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
      if (filesByModality[k] == null) {
        throw NeuroscanApiException('Missing file: $k');
      }
    }
    final res = await _withConnectivityFallback((base) async {
      final req = http.MultipartRequest('POST', _uriForBase(base, '/predict'));
      for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
        await _appendMultipartFile(req, k, filesByModality[k]!);
      }
      try {
        final streamed = await req.send().timeout(_segmentationMultipartTimeout);
        return await http.Response.fromStream(streamed).timeout(_segmentationMultipartTimeout);
      } on TimeoutException {
        _throwSegmentationTimedOut('View result (/predict)');
      }
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Web parity: local Alzheimer preview (`POST /api/analyses/alz-view-local`).
  static Future<Map<String, dynamic>> viewAlzheimerLocalResult({
    required int scanId,
    required PlatformFile imageFile,
  }) async {
    if (scanId <= 0) throw NeuroscanApiException('Invalid scan id');
    final lower = imageFile.name.toLowerCase();
    if (!lower.endsWith('.png') && !lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
      throw NeuroscanApiException('Choose a PNG/JPG image first.');
    }
    final authHeaders = await _headersAuthMultipart();
    final res = await _withConnectivityFallback((base) async {
      final req = http.MultipartRequest(
        'POST',
        _uriForBase(base, '/api/analyses/alz-view-local'),
      );
      req.headers.addAll(authHeaders);
      req.fields['scan_id'] = '$scanId';
      await _appendMultipartFile(req, 'image', imageFile);
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Patient/doctor clinic upload (`POST /mri/upload`).
  static Future<Map<String, dynamic>> sendScanToDoctor({
    required int scanId,
    required int doctorId,
  }) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/mri/send-to-doctor/$scanId'),
        headers: headers,
        body: json.encode({'doctor_id': doctorId}),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> runAnalysis(int scanId) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/api/analyses/run'),
        headers: headers,
        body: json.encode({'scan_id': scanId}),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendReport(int scanId) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/api/analyses/send-report/$scanId'),
        headers: headers,
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Web parity: `POST /api/generate-report` — server-side segmentation + PDF.
  static Future<Map<String, dynamic>> generateSegmentationReport({
    required int scanId,
    required int patientId,
    String? patientName,
    int? age,
    String? gender,
    bool? useCurrentResult,
    String? currentPrediction,
    double? currentConfidence,
    String? currentTumorVolume,
    Map<String, dynamic>? currentProbs,
    String? currentOutputImageUrl,
    String? currentModelVersion,
  }) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/api/generate-report'),
        headers: headers,
        body: json.encode({
          'scan_id': scanId,
          'patient_id': patientId,
          if (patientName != null) 'patient_name': patientName,
          if (age != null) 'age': age,
          if (gender != null) 'gender': gender,
          if (useCurrentResult != null) 'use_current_result': useCurrentResult,
          if (currentPrediction != null) 'current_prediction': currentPrediction,
          if (currentConfidence != null) 'current_confidence': currentConfidence,
          if (currentTumorVolume != null) 'current_tumor_volume': currentTumorVolume,
          if (currentProbs != null) 'current_probs': currentProbs,
          if (currentOutputImageUrl != null) 'current_output_image_url': currentOutputImageUrl,
          if (currentModelVersion != null) 'current_model_version': currentModelVersion,
        }),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Multipart `POST /api/generate-report` — same MONAI bundle pipeline as `POST /predict`.
  static Future<Map<String, dynamic>> generateSegmentationReportFromPredictUpload({
    required int scanId,
    required int patientId,
    String? patientName,
    int? age,
    String? gender,
    required Map<String, PlatformFile> filesByModality,
  }) async {
    for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
      if (filesByModality[k] == null) {
        throw NeuroscanApiException('Missing file: $k');
      }
    }
    final headers = await _headersAuthMultipart();
    // Use `/api/generate-report-from-predict` (explicit `File()` params) — same handler as
    // multipart `/api/generate-report` but avoids Starlette `request.form()` mis-parsing
    // some browser/Dart `http` file parts as plain fields ("Expected file upload for t1c").
    final res = await _withConnectivityFallback((base) async {
      final req = http.MultipartRequest(
        'POST',
        _uriForBase(base, '/api/generate-report-from-predict'),
      );
      req.headers.addAll(headers);
      req.fields['scan_id'] = '$scanId';
      req.fields['patient_id'] = '$patientId';
      if (patientName != null && patientName.isNotEmpty) {
        req.fields['patient_name'] = patientName;
      }
      if (age != null) req.fields['age'] = '$age';
      if (gender != null && gender.isNotEmpty) req.fields['gender'] = gender;
      for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
        await _appendMultipartFile(req, k, filesByModality[k]!);
      }
      try {
        final streamed = await req.send().timeout(_segmentationMultipartTimeout);
        return await http.Response.fromStream(streamed).timeout(_segmentationMultipartTimeout);
      } on TimeoutException {
        _throwSegmentationTimedOut('Generate report (PDF)');
      }
    });
    // Some backend builds expose only JSON POST /api/generate-report.
    // Fallback keeps doctor workflow functional without changing UI logic.
    if (res.statusCode == 404 || res.statusCode == 405) {
      return generateSegmentationReport(
        scanId: scanId,
        patientId: patientId,
        patientName: patientName,
        age: age,
        gender: gender,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Web parity: `POST /api/send-report` — deliver PDF to patient dashboard.
  static Future<Map<String, dynamic>> sendReportToPatient({
    required int reportId,
    required int patientId,
  }) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/api/send-report'),
        headers: headers,
        body: json.encode({
          'report_id': reportId,
          'patient_id': patientId,
        }),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Authenticated binary download (`GET /mri/scan/{id}/download`).
  static Future<({Uint8List bytes, String filename})> downloadPatientScanBytes(
    int scanId,
  ) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(
        _uriForBase(base, '/mri/scan/$scanId/download'),
        headers: headers,
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    final ctype = (res.headers['content-type'] ?? '').toLowerCase();
    var filename = ctype.contains('zip') ? 'scan_${scanId}_modalities.zip' : 'scan_$scanId';
    final cd = res.headers['content-disposition'];
    if (cd != null) {
      final q = RegExp(r'filename="([^"]+)"', caseSensitive: false).firstMatch(cd);
      if (q != null) {
        filename = q.group(1)!.trim();
      } else {
        final star = RegExp(r"filename\*=UTF-8''([^;\s]+)", caseSensitive: false).firstMatch(cd);
        if (star != null) {
          try {
            filename = Uri.decodeComponent(star.group(1)!);
          } catch (_) {
            filename = star.group(1)!;
          }
        }
      }
    } else if (ctype.contains('zip') && !filename.toLowerCase().endsWith('.zip')) {
      filename = 'scan_${scanId}_modalities.zip';
    }
    return (bytes: res.bodyBytes, filename: filename);
  }

  static Future<Map<String, dynamic>> createAdmin({
    required String email,
    required String password,
  }) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.post(
        _uriForBase(base, '/auth/create-admin'),
        headers: headers,
        body: json.encode({
          'email': email,
          'password': password,
          'role': 'admin',
        }),
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getMriPreviewMeta(int scanId) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(_uriForBase(base, '/mri/scan/$scanId/preview-meta'), headers: headers),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Uint8List> fetchMriPreviewPng(
    int scanId, {
    int? sliceIndex,
  }) async {
    final headers = await _headersJson(requireAuth: true);
    final res = await _withConnectivityFallback(
      (base) => http.get(
        _uriForBase(base, '/mri/scan/$scanId/preview').replace(
          queryParameters: {
            if (sliceIndex != null) 'slice_index': '$sliceIndex',
          },
        ),
        headers: headers,
      ),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return res.bodyBytes;
  }

  static String scanDownloadUrl(int scanId) {
    final base = _activeBaseUrl ?? NeuroscanApiConfig.baseUrl;
    return _uriForBase(base, '/mri/scan/$scanId/download').toString();
  }

  static Future<void> _appendMultipartFile(
    http.MultipartRequest req,
    String field,
    PlatformFile file,
  ) async {
    if (kIsWeb) {
      final fallbackName =
          field == 'mri_zip' ? 'patient_mri.zip' : '$field.bin';
      final filename =
          file.name.isNotEmpty ? file.name : fallbackName;
      // Prefer bytes: on web, `readStream` often shares a single-subscription source with `.bytes`.
      final bytes = file.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        req.files.add(
          http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
          ),
        );
        return;
      }
      final stream = file.readStream;
      if (stream != null && file.size > 0) {
        req.files.add(
          http.MultipartFile(
            field,
            stream,
            file.size,
            filename: filename,
          ),
        );
        return;
      }
      throw NeuroscanApiException(
        'Web upload failed for $field: file data not available. '
        'Re-select the ZIP or try the Windows/Android app if the file is large.',
      );
    }
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw NeuroscanApiException(
        'Upload failed for $field: file path missing. Please re-select the file.',
      );
    }
    req.files.add(await http.MultipartFile.fromPath(field, path));
  }

  static Future<Map<String, dynamic>> uploadMri({
    required Map<String, PlatformFile> filesByModality,
    int? doctorId,
  }) async {
    for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
      if (filesByModality[k] == null) {
        throw NeuroscanApiException('Missing file: $k');
      }
    }
    final authHeaders = await _headersAuthMultipart();
    final res = await _withConnectivityFallback((base) async {
      final req = http.MultipartRequest('POST', _uriForBase(base, '/mri/upload'));
      req.headers.addAll(authHeaders);
      if (doctorId != null && doctorId > 0) {
        req.fields['doctor_id'] = '$doctorId';
      }
      for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
        await _appendMultipartFile(req, k, filesByModality[k]!);
      }
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// True when the picked file clearly has bytes (client-side; server still validates).
  static Future<bool> patientZipLooksNonEmpty(PlatformFile zipFile) async {
    if (zipFile.size > 0) return true;
    final bytes = zipFile.bytes;
    if (bytes != null && bytes.isNotEmpty) return true;
    final path = zipFile.path;
    if (path != null && path.isNotEmpty) {
      final len = await patient_zip_path.patientZipFileLength(path);
      if (len != null && len > 0) return true;
    }
    return false;
  }

  /// Patient-friendly copy for known server errors (avoid alarming BraTS jargon where unhelpful).
  static String _patientZipServerMessage(String raw) {
    final t = raw.trim();
    final lower = t.toLowerCase();
    const modalityRequired =
        'all 4 mri modalities required: t1c, t1n, t2f, t2w';
    if (lower == modalityRequired || lower.startsWith(modalityRequired)) {
      return 'Upload could not be completed. Please try again or contact your clinic.';
    }
    // Old /mri/upload fallback when the ZIP part was not seen (e.g. outdated API) — not a patient/modality issue.
    if (lower.contains('provide mri_zip or all four') ||
        lower.contains('patient uploads must be a single zip')) {
      return 'The server did not accept this ZIP. Update the backend on the machine running the API '
          '(latest code exposes POST /mri/upload-zip and mri_zip on POST /mri/upload), then try again.';
    }
    return t;
  }

  /// Patient upload flow used by web dashboard: one ZIP containing MRI volumes.
  static Future<Map<String, dynamic>> uploadPatientMriZip({
    required PlatformFile zipFile,
    required int doctorId,
  }) async {
    if (doctorId <= 0) {
      throw NeuroscanApiException('Please select a doctor.');
    }
    final lower = zipFile.name.toLowerCase();
    if (!lower.endsWith('.zip')) {
      throw NeuroscanApiException('Please choose a .zip file.');
    }
    final authHeaders = await _headersAuthMultipart();
    Uint8List? webZipBytes;
    if (kIsWeb) {
      // Bytes-only on web: never subscribe to `readStream` (see file_picker / single-subscription).
      final raw = zipFile.bytes;
      if (raw == null || raw.isEmpty) {
        throw NeuroscanApiException(
          'Could not read this ZIP in the browser (no file data). '
          'Re-select the file, try a smaller ZIP, or use the Windows/Android app.',
        );
      }
      webZipBytes = Uint8List.fromList(raw);
    } else {
      if (!await patientZipLooksNonEmpty(zipFile)) {
        throw NeuroscanApiException('ZIP file is empty.');
      }
    }

    Future<http.Response> postPatientZip(String base, String path) async {
      final req = http.MultipartRequest('POST', _uriForBase(base, path));
      req.headers.addAll(authHeaders);
      req.fields['doctor_id'] = '$doctorId';
      if (webZipBytes != null) {
        final filename = zipFile.name.isNotEmpty ? zipFile.name : 'patient_mri.zip';
        req.files.add(
          http.MultipartFile.fromBytes(
            'mri_zip',
            webZipBytes,
            filename: filename,
          ),
        );
      } else {
        await _appendMultipartFile(req, 'mri_zip', zipFile);
      }
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    }

    final res = await _withConnectivityFallback((base) async {
      var r = await postPatientZip(base, '/mri/upload-zip');
      // Older APIs only have POST /mri/upload (no /upload-zip).
      if (r.statusCode == 404 || r.statusCode == 405) {
        r = await postPatientZip(base, '/mri/upload');
      }
      return r;
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        throw NeuroscanApiException(
          'Session expired or not signed in. Log in again, then upload your ZIP.',
        );
      }
      if (res.statusCode == 403) {
        throw NeuroscanApiException(
          'Upload was rejected (forbidden). Patient ZIP upload requires a patient account.',
        );
      }
      if (res.statusCode == 413) {
        throw NeuroscanApiException(
          'ZIP is too large for the server limit. Try a smaller archive or ask the clinic to raise the upload size.',
        );
      }
      throw NeuroscanApiException(
        _patientZipServerMessage(_messageFromResponse(res)),
      );
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// Alzheimer: single PNG/JPEG slice to selected doctor (`POST /mri/upload-alzheimer-png`).
  static Future<Map<String, dynamic>> uploadPatientAlzheimerPng({
    required PlatformFile pngFile,
    required int doctorId,
  }) async {
    if (doctorId <= 0) {
      throw NeuroscanApiException('Please select a doctor.');
    }
    final lower = pngFile.name.toLowerCase();
    if (!lower.endsWith('.png') &&
        !lower.endsWith('.jpg') &&
        !lower.endsWith('.jpeg') &&
        !lower.endsWith('.webp')) {
      throw NeuroscanApiException('Please choose a PNG or JPEG brain MRI image.');
    }
    final authHeaders = await _headersAuthMultipart();
    Uint8List? webBytes;
    if (kIsWeb) {
      final raw = pngFile.bytes;
      if (raw == null || raw.isEmpty) {
        throw NeuroscanApiException(
          'Could not read this image in the browser. Re-select the file.',
        );
      }
      webBytes = Uint8List.fromList(raw);
    }
    final res = await _withConnectivityFallback((base) async {
      final req = http.MultipartRequest(
        'POST',
        _uriForBase(base, '/mri/upload-alzheimer-png'),
      );
      req.headers.addAll(authHeaders);
      req.fields['doctor_id'] = '$doctorId';
      if (webBytes != null) {
        final fn = pngFile.name.isNotEmpty ? pngFile.name : 'mri.png';
        req.files.add(
          http.MultipartFile.fromBytes(
            'mri_png',
            webBytes,
            filename: fn,
          ),
        );
      } else {
        await _appendMultipartFile(req, 'mri_png', pngFile);
      }
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }
}
