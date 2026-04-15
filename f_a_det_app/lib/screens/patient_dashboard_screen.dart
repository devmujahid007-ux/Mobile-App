import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/mri_modalities.dart';
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

/// Patient workflow aligned with web `PatientDashboardPage.jsx`.
class PatientDashboardScreen extends StatefulWidget {
  const PatientDashboardScreen({super.key});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> {
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  String? _notice;
  List<Map<String, dynamic>> _scans = [];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _doctors = [];

  final Map<String, String?> _uploadPaths = {
    for (final k in mriModalityKeys) k: null,
  };
  int? _uploadDoctorId;
  final Map<int, int?> _doctorForScan = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await AuthGuard.redirectIfUnauthenticated(context);
      if (ok) await _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scans = await NeuroscanApi.getPatientScans();
      final reports = await NeuroscanApi.getPatientReports();
      final doctors = await NeuroscanApi.listDoctors();
      if (!mounted) return;
      setState(() {
        _scans = scans.whereType<Map<String, dynamic>>().toList();
        _reports = reports.whereType<Map<String, dynamic>>().toList();
        _doctors = doctors.whereType<Map<String, dynamic>>().toList();
        if (_doctors.length == 1) {
          final only = _parseId(_doctors.first['id']);
          _uploadDoctorId ??= only;
        }
        _loading = false;
      });
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _pendingScans =>
      _scans.where((s) => '${s['status']}'.toLowerCase() == 'pending').toList();

  List<Map<String, dynamic>> get _awaitingAnalysis => _scans
      .where((s) => '${s['status']}'.toLowerCase() == 'sent')
      .toList();

  List<Map<String, dynamic>> get _awaitingReport => _scans
      .where((s) => '${s['status']}'.toLowerCase() == 'analyzed')
      .toList();

  Future<void> _pickUpload(String key) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['nii', 'gz', 'dcm', 'dicom'],
    );
    if (res == null || res.files.isEmpty) return;
    final p = res.files.single.path;
    setState(() => _uploadPaths[key] = p);
  }

  Future<void> _submitUpload() async {
    for (final k in mriModalityKeys) {
      if (_uploadPaths[k] == null || _uploadPaths[k]!.isEmpty) {
        setState(() => _error = 'Choose all 4 MRI files (T1C, T1N, T2F, T2W).');
        return;
      }
    }
    if (_doctors.isEmpty) {
      setState(() => _error = 'No doctors registered yet. Ask an admin to add a doctor.');
      return;
    }
    if (_uploadDoctorId == null || _uploadDoctorId! <= 0) {
      setState(() => _error = 'Select which doctor should receive this MRI.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
      _notice = null;
    });
    try {
      await NeuroscanApi.uploadMri(
        filePathsByModality: {
          for (final e in _uploadPaths.entries) e.key: e.value!,
        },
        doctorId: _uploadDoctorId,
      );
      if (!mounted) return;
      setState(() {
        for (final k in mriModalityKeys) {
          _uploadPaths[k] = null;
        }
        _uploading = false;
        _notice = 'MRI uploaded and assigned to your doctor.';
      });
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _uploading = false;
      });
    }
  }

  Future<void> _sendPendingToDoctor(int scanId) async {
    final docId = _doctorForScan[scanId];
    if (docId == null || docId <= 0) {
      setState(() => _error = 'Pick a doctor for this scan first.');
      return;
    }
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      await NeuroscanApi.sendScanToDoctor(scanId: scanId, doctorId: docId);
      if (!mounted) return;
      setState(() => _notice = 'Scan #$scanId sent to doctor.');
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Widget _stat(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: NeuroScanColors.blue600, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 10,
                      color: NeuroScanColors.slate500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: NeuroScanColors.slate800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  if (_error != null)
                    Material(
                      color: NeuroScanColors.red50,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: NeuroScanColors.red700),
                        ),
                      ),
                    ),
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _notice!,
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stat('Scans', '${_scans.length}', Icons.cloud_upload_outlined),
                      const SizedBox(width: 8),
                      _stat('Reports', '${_reports.length}', Icons.check_circle_outline),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stat('With doctor', '${_awaitingAnalysis.length}', Icons.send_outlined),
                      const SizedBox(width: 8),
                      _stat('Pending send', '${_pendingScans.length}', Icons.schedule),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _stat('Report pending', '${_awaitingReport.length}', Icons.description_outlined),
                      const SizedBox(width: 8),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                  if (_pendingScans.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Material(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${_pendingScans.length} scan(s) are not assigned to a doctor. '
                          'Pick a doctor below and tap Send to doctor.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Upload MRI (4 modalities)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: NeuroScanColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_doctors.isEmpty)
                    const Text(
                      'No doctors available. Register a doctor account first.',
                      style: TextStyle(color: NeuroScanColors.slate600),
                    )
                  else ...[
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Doctor who receives this MRI',
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
                                DropdownMenuItem(
                                  value: _parseId(d['id']),
                                  child: Text('${d['name'] ?? d['email']}'),
                                ),
                          ],
                          onChanged: _uploading
                              ? null
                              : (v) => setState(() => _uploadDoctorId = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final k in mriModalityKeys) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(mriModalityLabels[k] ?? k),
                        subtitle: Text(
                          _uploadPaths[k] == null
                              ? 'No file'
                              : _uploadPaths[k]!.split(RegExp(r'[/\\]')).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: _uploading ? null : () => _pickUpload(k),
                          child: const Text('Browse'),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _uploading ? null : _submitUpload,
                      child: _uploading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Upload & send to doctor'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Your scans',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: NeuroScanColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_scans.isEmpty)
                    const Text(
                      'No scans yet.',
                      style: TextStyle(color: NeuroScanColors.slate500),
                    )
                  else
                    ..._scans.map((s) {
                      final id = _parseId(s['id']) ?? 0;
                      final st = '${s['status']}';
                      final pending = st.toLowerCase() == 'pending';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Scan #$id · $st',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (pending && _doctors.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                DropdownButton<int>(
                                  value: _doctorForScan[id],
                                  isExpanded: true,
                                  hint: const Text('Assign doctor'),
                                  items: [
                                    for (final d in _doctors)
                                      if (_parseId(d['id']) != null)
                                        DropdownMenuItem(
                                          value: _parseId(d['id']),
                                          child: Text('${d['name'] ?? d['email']}'),
                                        ),
                                  ],
                                  onChanged: (v) => setState(
                                    () => _doctorForScan[id] = v,
                                  ),
                                ),
                                FilledButton.tonal(
                                  onPressed: id == 0
                                      ? null
                                      : () => _sendPendingToDoctor(id),
                                  child: const Text('Send to doctor'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  const Text(
                    'Completed reports',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: NeuroScanColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_reports.isEmpty)
                    const Text(
                      'No finalized reports yet.',
                      style: TextStyle(color: NeuroScanColors.slate500),
                    )
                  else
                    ..._reports.map((r) {
                      final rid = _parseId(r['report_id']);
                      final dl = '${r['download_url'] ?? ''}';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['prediction'] ?? 'Report'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Confidence: ${r['confidence']}% · ${r['file_name'] ?? ''}',
                                style: const TextStyle(
                                  color: NeuroScanColors.slate600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (rid != null)
                                    OutlinedButton(
                                      onPressed: () => Navigator.pushNamed(
                                        context,
                                        '/results',
                                        arguments: {'id': rid},
                                      ),
                                      child: const Text('View'),
                                    ),
                                  if (dl.isNotEmpty)
                                    FilledButton.tonal(
                                      onPressed: () {
                                        final url = NeuroscanApi.absoluteUrl(dl);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: SelectableText(url),
                                          ),
                                        );
                                      },
                                      child: const Text('PDF link'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
