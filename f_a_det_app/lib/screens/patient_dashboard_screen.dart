import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_guard.dart';
import '../services/neuroscan_api.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_drawer.dart';
import '../widgets/neuroscan_shell.dart';

int? _parseId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}

bool _isLikelyNotFoundMessage(String? message) {
  final m = (message ?? '').toLowerCase();
  return m.contains('not found') || m.contains('404');
}

Map<String, dynamic> _normalizeReportEntry(Map<String, dynamic> r) {
  return {
    ...r,
    'id': _parseId(r['id']),
    'scan_id': _parseId(r['scan_id']),
  };
}

/// Aligns `GET /api/analyses/patient-reports` rows with `/reports` list shape.
Map<String, dynamic> _normalizePatientReportEntry(Map<String, dynamic> r) {
  final id = _parseId(r['report_id']) ?? _parseId(r['id']);
  return {
    ...r,
    'id': id,
    'scan_id': _parseId(r['scan_id']),
  };
}

bool _scanIsAlzheimer(Map<String, dynamic> s) =>
    '${s['scan_kind']}'.toLowerCase() == 'alzheimer';

/// Patient workflow aligned with web `PatientDashboardPage.jsx`.
class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> {
  bool _loading = true;
  bool _uploading = false;
  String? _reportsInfo;
  String? _reportsError;
  String? _doctorsFetchError;
  List<Map<String, dynamic>> _scans = [];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _doctors = [];
  Set<int>? _deletingScanIds;

  PlatformFile? _zipFile;
  int? _uploadDoctorId;

  /// Brain tumor (ZIP) vs Alzheimer (PNG slice).
  int _sectionIndex = 0;

  PlatformFile? _pngFile;
  bool _uploadingAlz = false;
  int? _uploadDoctorIdAlz;

  @override
  void initState() {
    super.initState();
    _deletingScanIds ??= <int>{};
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await AuthGuard.redirectIfUnauthenticated(context);
      if (ok) await _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _reportsInfo = null;
      _reportsError = null;
      _doctorsFetchError = null;
    });

    String? criticalError;
    var scans = <Map<String, dynamic>>[];
    var reports = <Map<String, dynamic>>[];
    var doctors = <Map<String, dynamic>>[];
    String? reportsInfo;
    String? reportsError;
    String? doctorsFetchError;

    try {
      final raw = await NeuroscanApi.getPatientScans();
      scans = raw.whereType<Map<String, dynamic>>().toList();
    } on NeuroscanApiException catch (e) {
      criticalError = e.message;
    } catch (e) {
      criticalError = '$e';
    }

    if (criticalError == null) {
      try {
        final raw = await NeuroscanApi.listReports();
        reports = raw.whereType<Map<String, dynamic>>().map(_normalizeReportEntry).toList();
      } on NeuroscanApiException catch (e) {
        if (_isLikelyNotFoundMessage(e.message)) {
          try {
            final raw = await NeuroscanApi.getPatientReports();
            reports = raw.whereType<Map<String, dynamic>>().map(_normalizePatientReportEntry).toList();
            reportsInfo =
                'This server does not expose GET /reports; showing reports from the legacy patient-reports endpoint.';
          } on NeuroscanApiException catch (e2) {
            reportsError = e2.message;
          } catch (e2) {
            reportsError = '$e2';
          }
        } else {
          reportsError = e.message;
        }
      } catch (e) {
        reportsError = '$e';
      }
    }

    try {
      final raw = await NeuroscanApi.listDoctors();
      doctors = raw.whereType<Map<String, dynamic>>().toList();
    } on NeuroscanApiException catch (e) {
      doctors = [];
      doctorsFetchError = e.message;
    } catch (e) {
      doctors = [];
      doctorsFetchError = '$e';
    }

    if (!mounted) return;
    setState(() {
      _scans = scans;
      _reports = reports;
      _doctors = doctors;
      _reportsInfo = reportsInfo;
      _reportsError = reportsError;
      _doctorsFetchError = doctorsFetchError;
      if (_doctors.length == 1) {
        _uploadDoctorId ??= _parseId(_doctors.first['id']);
        _uploadDoctorIdAlz ??= _parseId(_doctors.first['id']);
      }
      _loading = false;
    });
    if (criticalError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(criticalError)),
      );
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? NeuroScanColors.red700 : null,
      ),
    );
  }

  List<Map<String, dynamic>> get _scansTumor =>
      _scans.where((s) => !_scanIsAlzheimer(s)).toList();
  List<Map<String, dynamic>> get _scansAlz =>
      _scans.where((s) => _scanIsAlzheimer(s)).toList();

  List<Map<String, dynamic>> _pendingFor(List<Map<String, dynamic>> list) => list
      .where((s) => '${s['status']}'.toLowerCase() == 'pending')
      .toList();
  List<Map<String, dynamic>> _withDoctorFor(List<Map<String, dynamic>> list) =>
      list
          .where((s) => '${s['status']}'.toLowerCase() == 'sent')
          .toList()
        ..addAll(
          list.where((s) => '${s['status']}'.toLowerCase() == 'analyzed'),
        );

  int get _openRequestsCountTumor => _withDoctorFor(_scansTumor).length;
  int get _openRequestsCountAlz => _withDoctorFor(_scansAlz).length;
  int get _reportsReceivedCount => _reports.length;
  int get _totalCasesCountTumor => _scansTumor.length;
  int get _totalCasesCountAlz => _scansAlz.length;

  Future<void> _pickZip() async {
    // Web + mobile: load file bytes in the picker. Using readStream on web often triggers
    // "Stream has already been listened to" (single-subscription stream reused by the plugin).
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() => _zipFile = res.files.single);
  }

  Future<void> _uploadZip() async {
    if (_zipFile == null) {
      _snack('Choose a .zip file to send to your doctor.', error: true);
      return;
    }
    final name = _zipFile!.name.toLowerCase();
    if (!name.endsWith('.zip')) {
      _snack('Only .zip archives are accepted.', error: true);
      return;
    }
    // Empty ZIP is validated inside uploadPatientMriZip.
    if (_doctors.isEmpty) {
      _snack('No doctors are available yet. Ask admin to add a doctor.', error: true);
      return;
    }
    if (_uploadDoctorId == null || _uploadDoctorId! <= 0) {
      _snack('Select which doctor should receive this MRI.', error: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final created = await NeuroscanApi.uploadPatientMriZip(
        zipFile: _zipFile!,
        doctorId: _uploadDoctorId!,
      );
      if (!mounted) return;
      final createdId = _parseId(created['id']);
      final createdDoctor = _parseId(created['doctor_id']) ?? _uploadDoctorId;
      setState(() {
        _uploading = false;
        _zipFile = null;
        _uploadDoctorId = null;
      });
      _snack(
        createdId == null
            ? 'MRI ZIP uploaded and sent to your doctor.'
            : 'Scan #$createdId uploaded and sent to doctor ID $createdDoctor.',
      );
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack(e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('$e', error: true);
    }
  }

  Future<void> _pickPng() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() => _pngFile = res.files.single);
  }

  Future<void> _uploadAlzPng() async {
    if (_pngFile == null) {
      _snack('Choose a PNG or JPEG brain MRI image.', error: true);
      return;
    }
    final name = _pngFile!.name.toLowerCase();
    if (!name.endsWith('.png') &&
        !name.endsWith('.jpg') &&
        !name.endsWith('.jpeg') &&
        !name.endsWith('.webp')) {
      _snack('Only PNG or JPEG images are accepted.', error: true);
      return;
    }
    if (_doctors.isEmpty) {
      _snack('No doctors are available yet. Ask admin to add a doctor.', error: true);
      return;
    }
    if (_uploadDoctorIdAlz == null || _uploadDoctorIdAlz! <= 0) {
      _snack('Select which doctor should receive this MRI.', error: true);
      return;
    }
    setState(() => _uploadingAlz = true);
    try {
      final created = await NeuroscanApi.uploadPatientAlzheimerPng(
        pngFile: _pngFile!,
        doctorId: _uploadDoctorIdAlz!,
      );
      if (!mounted) return;
      final createdId = _parseId(created['id']);
      final createdDoctor = _parseId(created['doctor_id']) ?? _uploadDoctorIdAlz;
      setState(() {
        _uploadingAlz = false;
        _pngFile = null;
        _uploadDoctorIdAlz = null;
      });
      _snack(
        createdId == null
            ? 'MRI image uploaded and sent to your doctor.'
            : 'Alzheimer scan #$createdId sent to doctor ID $createdDoctor.',
      );
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _uploadingAlz = false);
      _snack(e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingAlz = false);
      _snack('$e', error: true);
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'pending';
      case 'sent':
        return 'sent';
      case 'analyzed':
        return 'analyzed';
      case 'reported':
        return 'reported';
      default:
        return status.toLowerCase();
    }
  }

  Color _statusBg(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.yellow.shade100;
      case 'sent':
        return Colors.blue.shade100;
      case 'analyzed':
        return Colors.purple.shade100;
      case 'reported':
        return Colors.green.shade100;
      default:
        return NeuroScanColors.slate100;
    }
  }

  Color _statusFg(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.yellow.shade900;
      case 'sent':
        return Colors.blue.shade900;
      case 'analyzed':
        return Colors.purple.shade900;
      case 'reported':
        return Colors.green.shade900;
      default:
        return NeuroScanColors.slate700;
    }
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: NeuroScanColors.blue50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: NeuroScanColors.blue600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate500)),
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: NeuroScanColors.slate800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _doctorText(Map<String, dynamic>? doctor) {
    if (doctor == null) return '—';
    final name = '${doctor['name'] ?? ''}'.trim();
    final email = '${doctor['email'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return 'Doctor';
  }

  String _fmtDate(dynamic raw) {
    final s = raw?.toString() ?? '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return 'Unknown';
    final l = dt.toLocal();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${t(l.month)}-${t(l.day)} ${t(l.hour)}:${t(l.minute)}';
  }

  Future<void> _openReport(Map<String, dynamic> linked) async {
    final rel = '${linked['download_url'] ?? ''}'.trim();
    if (rel.isNotEmpty) {
      final url = NeuroscanApi.absoluteUrl(rel);
      final uri = Uri.tryParse(url);
      if (uri == null) {
        _snack('Invalid report URL.', error: true);
        return;
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      _snack('Could not open report URL.', error: true);
      return;
    }
    final reportId = _parseId(linked['id']) ?? 0;
    if (reportId <= 0) {
      if (!mounted) return;
      _snack('Report is missing an id; try refreshing.', error: true);
      return;
    }
    try {
      final url = await NeuroscanApi.reportPdfOpenUrl(
        reportId,
        download: true,
        cacheBust: DateTime.now().millisecondsSinceEpoch,
      );
      final uri = Uri.tryParse(url);
      if (uri == null) {
        _snack('Invalid report URL.', error: true);
        return;
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _snack('Could not open report URL.', error: true);
      }
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      _snack(e.message, error: true);
    }
  }

  Future<void> _deleteScanRequest(Map<String, dynamic> scan) async {
    final scanId = _parseId(scan['id']) ?? 0;
    if (scanId <= 0) {
      _snack('Invalid scan id.', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete request?'),
        content: const Text(
          'This will remove the request from both patient and doctor sides.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => (_deletingScanIds ??= <int>{}).add(scanId));
    try {
      await NeuroscanApi.deletePatientScan(scanId);
      if (!mounted) return;
      _snack('Request deleted successfully.');
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      _snack(e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      _snack('$e', error: true);
    } finally {
      if (mounted) {
        setState(() => (_deletingScanIds ??= <int>{}).remove(scanId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportByScanId = <int, Map<String, dynamic>>{};
    for (final r in _reports) {
      final sid = _parseId(r['scan_id']);
      if (sid != null) reportByScanId[sid] = r;
    }
    final scansForMode = _sectionIndex == 0 ? _scansTumor : _scansAlz;
    final reportsForMode = _reports.where((r) {
      final sid = _parseId(r['scan_id']);
      if (sid == null) return false;
      final s = _scans.where((e) => _parseId(e['id']) == sid);
      if (s.isEmpty) return false;
      return _sectionIndex == 0 ? !_scanIsAlzheimer(s.first) : _scanIsAlzheimer(s.first);
    }).toList();

    return NeuroScanShell(
      title: 'Patient Dashboard',
      authSlot: NeuroScanAuthSlot.account,
      additionalActions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_reportsInfo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NeuroScanColors.blue50.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NeuroScanColors.blue100),
                      ),
                      child: Text(_reportsInfo!, style: const TextStyle(color: NeuroScanColors.slate700, fontSize: 13)),
                    ),
                  if (_reportsError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        'Reports could not be loaded: $_reportsError',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment<int>(
                          value: 0,
                          label: Text('Brain tumor'),
                          icon: Icon(Icons.folder_zip_outlined, size: 18),
                        ),
                        ButtonSegment<int>(
                          value: 1,
                          label: Text('Alzheimer'),
                          icon: Icon(Icons.psychology_alt_outlined, size: 18),
                        ),
                      ],
                      selected: {_sectionIndex},
                      onSelectionChanged: (s) => setState(() => _sectionIndex = s.first),
                    ),
                  ),

                  Row(
                    children: [
                      _statCard(
                        'Open Requests',
                        '${_sectionIndex == 0 ? _openRequestsCountTumor : _openRequestsCountAlz}',
                        Icons.cloud_upload_outlined,
                      ),
                      const SizedBox(width: 8),
                      _statCard('Reports Received', '$_reportsReceivedCount', Icons.description_outlined),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _statCard(
                        'Total Cases',
                        '${_sectionIndex == 0 ? _totalCasesCountTumor : _totalCasesCountAlz}',
                        Icons.check_circle_outline,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: SizedBox()),
                    ],
                  ),

                  if (_sectionIndex == 0 && _pendingFor(_scansTumor).isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        '${_pendingFor(_scansTumor).length} older tumor scan(s) are not linked to a doctor. New uploads always include a doctor.',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                  if (_sectionIndex == 1 && _pendingFor(_scansAlz).isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        '${_pendingFor(_scansAlz).length} older Alzheimer scan(s) are not linked to a doctor. New uploads always include a doctor.',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ),
                  ],

                  if (_sectionIndex == 0) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '1 · Brain tumor — Upload MRI (ZIP)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: NeuroScanColors.slate800),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _uploading ? null : _pickZip,
                          child: Ink(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: NeuroScanColors.blue400, width: 1.2),
                              color: NeuroScanColors.blue50.withValues(alpha: 0.35),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.upload_file, color: NeuroScanColors.blue600, size: 30),
                                const SizedBox(height: 8),
                                const Text('MRI scans as one .zip', style: TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(
                                  _zipFile == null ? 'Choose ZIP file' : _zipFile!.name,
                                  style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Upload your MRI scans as a ZIP file. Your doctor will review and process it.',
                          style: TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                        ),
                        const SizedBox(height: 12),
                        if (_doctorsFetchError != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Text(
                              'Doctor list failed to load ($_doctorsFetchError). Check that the API includes GET /api/patients/doctors and your account can access it.',
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                            ),
                          )
                        else if (_doctors.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Text(
                              'No doctors are available. Register at least one doctor account before patients can upload.',
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                            ),
                          )
                        else
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Doctor who will receive this MRI',
                              border: OutlineInputBorder(),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _uploadDoctorId,
                                isExpanded: true,
                                hint: const Text('Select doctor'),
                                items: [
                                  for (final d in _doctors)
                                    if (_parseId(d['id']) != null)
                                      DropdownMenuItem<int>(
                                        value: _parseId(d['id']),
                                        child: Text('${d['name'] ?? d['email']} | ID ${d['id']}'),
                                      ),
                                ],
                                onChanged: _uploading ? null : (v) => setState(() => _uploadDoctorId = v),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _uploading ||
                                  _zipFile == null ||
                                  _doctors.isEmpty ||
                                  _doctorsFetchError != null ||
                                  _uploadDoctorId == null
                              ? null
                              : _uploadZip,
                          child: _uploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Upload ZIP & send to doctor'),
                        ),
                      ],
                    ),
                  ),
                  ],

                  if (_sectionIndex == 1) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '2 · Alzheimer — Upload MRI (PNG / JPEG)',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: NeuroScanColors.slate800),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _uploadingAlz ? null : _pickPng,
                            child: Ink(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: NeuroScanColors.blue400, width: 1.2),
                                color: NeuroScanColors.blue50.withValues(alpha: 0.35),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.image_outlined, color: NeuroScanColors.blue600, size: 30),
                                  const SizedBox(height: 8),
                                  const Text('Brain MRI slice as .png or .jpeg', style: TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _pngFile == null ? 'Choose image file' : _pngFile!.name,
                                    style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Upload one axial or representative MRI slice. Your doctor will run Alzheimer screening and send a report.',
                            style: TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                          ),
                          const SizedBox(height: 12),
                          if (_doctorsFetchError != null)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Text(
                                'Doctor list failed to load ($_doctorsFetchError).',
                                style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                              ),
                            )
                          else if (_doctors.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Text(
                                'No doctors are available. Register at least one doctor account before patients can upload.',
                                style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                              ),
                            )
                          else
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Doctor who will receive this MRI',
                                border: OutlineInputBorder(),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _uploadDoctorIdAlz,
                                  isExpanded: true,
                                  hint: const Text('Select doctor'),
                                  items: [
                                    for (final d in _doctors)
                                      if (_parseId(d['id']) != null)
                                        DropdownMenuItem<int>(
                                          value: _parseId(d['id']),
                                          child: Text('${d['name'] ?? d['email']} | ID ${d['id']}'),
                                        ),
                                  ],
                                  onChanged: _uploadingAlz ? null : (v) => setState(() => _uploadDoctorIdAlz = v),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _uploadingAlz ||
                                    _pngFile == null ||
                                    _doctors.isEmpty ||
                                    _doctorsFetchError != null ||
                                    _uploadDoctorIdAlz == null
                                ? null
                                : _uploadAlzPng,
                            child: _uploadingAlz
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Upload image & send to doctor'),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _sectionIndex == 0 ? 'My scans (Tumor)' : 'My scans (Alzheimer)',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: NeuroScanColors.slate800),
                              ),
                            ),
                            Text(
                              '${scansForMode.length} total',
                              style: const TextStyle(color: NeuroScanColors.slate500, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_sectionIndex == 0)
                          const Text(
                            'Requests you sent to your doctor. Pending is not yet with a doctor; Sent means clinic has your case; Reported means report is finalized.',
                            style: TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                          )
                        else
                          const Text(
                            'Status mirrors your doctor workflow. Reported means PDF is ready in Reports from your doctor.',
                            style: TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                          ),
                        const SizedBox(height: 10),
                        if (scansForMode.isEmpty)
                          Text(
                            _sectionIndex == 0
                                ? 'Upload a ZIP to create your first tumor case.'
                                : 'Upload a PNG or JPEG to create your first Alzheimer case.',
                            style: const TextStyle(color: NeuroScanColors.slate500),
                          )
                        else
                          ...scansForMode.map((scan) {
                            final id = _parseId(scan['id']) ?? 0;
                            final status = '${scan['status'] ?? ''}';
                            final deleting = (_deletingScanIds ?? const <int>{}).contains(id);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: NeuroScanColors.slate50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Scan ID $id', style: const TextStyle(fontSize: 11, color: NeuroScanColors.slate500)),
                                        Text(
                                          '${scan['file_name'] ?? 'File #$id'}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, color: NeuroScanColors.slate800),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Doctor: ${scan['doctor'] is Map ? _doctorText((scan['doctor'] as Map).cast<String, dynamic>()) : (status.toLowerCase() == 'pending' ? 'Not assigned' : '—')}',
                                          style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate600),
                                        ),
                                        Text(
                                          'Uploaded: ${_fmtDate(scan['upload_date'])}${scan['sent_date'] != null ? ' · Sent: ${_fmtDate(scan['sent_date'])}' : ''}',
                                          style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: _statusBg(status),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _statusLabel(status),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: _statusFg(status),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      OutlinedButton(
                                        onPressed: deleting ? null : () => _deleteScanRequest(scan),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: NeuroScanColors.red700,
                                          side: BorderSide(color: Colors.red.shade300),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          minimumSize: const Size(0, 0),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: deleting
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade100),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Reports from your doctor',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: NeuroScanColors.slate800),
                              ),
                            ),
                            Text(
                              '${reportsForMode.length} in this module',
                              style: const TextStyle(color: NeuroScanColors.slate500, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'PDF reports your doctor has sent to you. Use Download PDF to save the file.',
                          style: TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                        ),
                        const SizedBox(height: 10),
                        if (reportsForMode.isEmpty)
                          Text(
                            _sectionIndex == 0
                                ? 'No reports yet for tumor cases.'
                                : 'No reports yet for Alzheimer cases.',
                            style: const TextStyle(color: NeuroScanColors.slate500),
                          )
                        else
                          ...reportsForMode.map((rep) {
                            final rid = _parseId(rep['id']) ?? 0;
                            final sid = _parseId(rep['scan_id']) ?? 0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: NeuroScanColors.slate50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Report #$rid · Scan #$sid',
                                          style: const TextStyle(fontWeight: FontWeight.w600, color: NeuroScanColors.slate800),
                                        ),
                                        Text(
                                          'Doctor: ${rep['doctor_name'] ?? '—'}'
                                          '${rep['created_at'] != null ? ' · ${_fmtDate(rep['created_at'])}' : ''}',
                                          style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                                    onPressed: rid > 0
                                        ? () {
                                            final linked = reportByScanId[sid] ?? rep;
                                            _openReport(linked);
                                          }
                                        : null,
                                    child: const Text('Download PDF'),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
