import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_storage.dart';
import 'neuroscan_api_config.dart';

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

  static String absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return resolveMediaUrl(path);
    final base = NeuroscanApiConfig.baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  /// `/predict` returns absolute URLs with `127.0.0.1`; rewrite for emulator/LAN.
  static String resolveMediaUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    if (parsed.host == '127.0.0.1' || parsed.host == 'localhost') {
      final b = Uri.parse(NeuroscanApiConfig.baseUrl);
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
        final err = m['error'];
        if (err != null) return '$err';
        final d = parseFastApiDetail(m);
        if (d != null && d.isNotEmpty) return d;
      }
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }

  /// Browser / mobile "no route to host" style failures (never an HTTP body).
  static NeuroscanApiException _connectionFailed(Object error) {
    final base = NeuroscanApiConfig.baseUrl;
    return NeuroscanApiException(
      'Cannot reach the API at $base\n\n'
      '• If you use Flutter Web (Chrome) on THIS PC, try:\n'
      '  flutter run -d chrome --dart-define=NEUROSCAN_API_URL=http://127.0.0.1:8000\n'
      '  (Chrome often blocks localhost → 192.168.x.x.)\n\n'
      '• Start the API (same PC): cd backend && uvicorn main:app --host 0.0.0.0 --port 8000\n'
      '  Pull latest backend — it sends Access-Control-Allow-Private-Network for Chrome.\n\n'
      '• Windows Firewall: allow inbound TCP 8000.\n\n'
      '• Test: open $base/docs in a browser on the device running the app.',
    );
  }

  static bool _isConnectivityFailure(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('failed to fetch') ||
        s.contains('clientexception') ||
        s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('network is unreachable') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('host lookup failed') ||
        s.contains('failed host lookup') ||
        s.contains('network error');
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('${NeuroscanApiConfig.baseUrl}/auth/login'),
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw NeuroscanApiException(_messageFromResponse(res));
      }
      return json.decode(res.body) as Map<String, dynamic>;
    } on NeuroscanApiException {
      rethrow;
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
      final res = await http.post(
        Uri.parse('${NeuroscanApiConfig.baseUrl}/auth/register'),
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode(body),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw NeuroscanApiException(_messageFromResponse(res));
      }
      return json.decode(res.body) as Map<String, dynamic>;
    } on NeuroscanApiException {
      rethrow;
    } catch (e) {
      if (_isConnectivityFailure(e)) throw _connectionFailed(e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> me() async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/auth/me'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getRecentAnalyses({int limit = 6}) async {
    final headers = await _headersJson();
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/api/analyses/recent?limit=$limit'),
      headers: headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getAnalysis(int reportId) async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/api/analyses/$reportId'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> listDoctors() async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/api/patients/doctors'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getPatientScans() async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/mri/patient-scans'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getPatientReports() async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/api/analyses/patient-reports'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getDoctorRequests() async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/mri/doctor-requests'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/api/stats/summary'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> listUsers() async {
    final res = await http.get(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/users/'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as List<dynamic>;
  }

  /// Public BraTS-style segmentation (`POST /predict`) — no JWT.
  static Future<Map<String, dynamic>> predictTumorSegmentation(
    Map<String, String> filePathsByModality,
  ) async {
    for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
      if (filePathsByModality[k] == null || filePathsByModality[k]!.isEmpty) {
        throw NeuroscanApiException('Missing file: $k');
      }
    }
    final uri = Uri.parse('${NeuroscanApiConfig.baseUrl}/predict');
    final req = http.MultipartRequest('POST', uri);
    for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
      req.files.add(await http.MultipartFile.fromPath(k, filePathsByModality[k]!));
    }
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
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
    final res = await http.post(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/mri/send-to-doctor/$scanId'),
      headers: await _headersJson(requireAuth: true),
      body: json.encode({'doctor_id': doctorId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> runAnalysis(int scanId) async {
    final res = await http.post(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/api/analyses/run'),
      headers: await _headersJson(requireAuth: true),
      body: json.encode({'scan_id': scanId}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendReport(int scanId) async {
    final res = await http.post(
      Uri.parse('${NeuroscanApiConfig.baseUrl}/api/analyses/send-report/$scanId'),
      headers: await _headersJson(requireAuth: true),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> uploadMri({
    required Map<String, String> filePathsByModality,
    int? doctorId,
  }) async {
    for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
      if (filePathsByModality[k] == null || filePathsByModality[k]!.isEmpty) {
        throw NeuroscanApiException('Missing file: $k');
      }
    }
    final uri = Uri.parse('${NeuroscanApiConfig.baseUrl}/mri/upload');
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(await _headersAuthMultipart());
    if (doctorId != null && doctorId > 0) {
      req.fields['doctor_id'] = '$doctorId';
    }
    for (final k in const ['t1c', 't1n', 't2f', 't2w']) {
      req.files.add(await http.MultipartFile.fromPath(k, filePathsByModality[k]!));
    }
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NeuroscanApiException(_messageFromResponse(res));
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }
}
