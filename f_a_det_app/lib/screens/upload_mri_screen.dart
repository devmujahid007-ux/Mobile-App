import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/mri_modalities.dart';
import '../services/auth_storage.dart';
import '../services/neuroscan_api.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_shell.dart';

/// BraTS four-modality flow.
/// - **Patient:** ZIP upload lives on Patient Dashboard (DB scan).
/// - **Doctor / admin:** can **save** scan + segmentation + PDF + diagnosis/report rows (same as doctor dashboard pipeline),
///   or run a **quick preview** via public `POST /predict` (nothing persisted).
class UploadMRIScreen extends StatefulWidget {
  const UploadMRIScreen({super.key});

  @override
  State<UploadMRIScreen> createState() => _UploadMRIScreenState();
}

class _UploadMRIScreenState extends State<UploadMRIScreen> {
  final Map<String, PlatformFile?> _files = {
    for (final k in mriModalityKeys) k: null,
  };

  static const _labels = {
    't1c': 'T1C (t1ce)',
    't1n': 'T1N',
    't2f': 'FLAIR (t2f)',
    't2w': 'T2W',
  };

  bool _busy = false;
  String? _message;
  bool _error = false;
  String? _outputImageUrl;
  bool _isPatient = false;
  String _role = '';
  List<Map<String, dynamic>> _patients = [];
  int? _patientId;

  bool get _showClinicSave =>
      !_isPatient &&
      (_role == 'doctor' || _role == 'admin' || _role == 'superadmin');

  bool _allNiftiForClinic() {
    for (final k in mriModalityKeys) {
      final n = (_files[k]?.name ?? '').toLowerCase();
      if (!(n.endsWith('.nii') || n.endsWith('.nii.gz'))) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final t = await AuthStorage.getToken();
    if (t == null || t.isEmpty) {
      if (mounted) {
        setState(() {
          _role = '';
          _isPatient = false;
        });
      }
      return;
    }
    try {
      final me = await NeuroscanApi.me();
      final role = (me['role'] as String? ?? '').toLowerCase();
      if (!mounted) return;
      setState(() {
        _role = role;
        _isPatient = role == 'patient';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _role = '';
          _isPatient = false;
        });
      }
      return;
    }

    // Keep working like before: patient list is optional; failure must not wipe role/session.
    if (!_showClinicSave) return;
    try {
      final rows = await NeuroscanApi.listPatients();
      if (!mounted) return;
      setState(() {
        _patients = rows.whereType<Map<String, dynamic>>().toList();
      });
    } catch (_) {
      if (mounted) setState(() => _patients = []);
    }
  }

  Future<void> _pick(String key) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['nii', 'gz', 'dcm', 'dicom'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    setState(() {
      _files[key] = f;
      _message = null;
      _outputImageUrl = null;
    });
  }

  bool _allSet() => _files.values.every((f) => f != null);

  Map<String, PlatformFile> _filesMap() {
    return {
      for (final e in _files.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  int? _patientDropdownId(Map<String, dynamic> p) {
    final raw = p['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  /// Public `POST /predict` — no database writes.
  Future<void> _runPredict() async {
    if (!_allSet()) {
      setState(() {
        _error = true;
        _message = 'Select all four MRI files (.nii / .nii.gz / .dcm).';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
      _message = null;
      _outputImageUrl = null;
    });
    try {
      final out = await NeuroscanApi.predictTumorSegmentation(_filesMap());
      final img = out['output_image']?.toString();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outputImageUrl =
            img != null ? NeuroscanApi.resolveMediaUrl(img) : null;
        _message = '${out['message'] ?? 'Done'} (preview only — not saved to database)';
      });
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = '$e';
      });
    }
  }

  /// `POST /mri/upload` + `POST /api/generate-report-from-predict` — MRIScan, Diagnosis, Report, PDF on disk.
  Future<void> _runSaveToClinic() async {
    if (!_allSet()) {
      setState(() {
        _error = true;
        _message = 'Select all four MRI files.';
      });
      return;
    }
    if (_patientId == null) {
      setState(() {
        _error = true;
        _message = 'Choose a patient — results are stored under that patient in the database.';
      });
      return;
    }
    if (!_allNiftiForClinic()) {
      setState(() {
        _error = true;
        _message =
            'Clinic save requires NIfTI (.nii / .nii.gz) for all four modalities (same as the PDF pipeline). '
            'Use Quick preview for DICOM-only experiments.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
      _message = null;
      _outputImageUrl = null;
    });
    try {
      final up = await NeuroscanApi.uploadMri(filesByModality: _filesMap());
      final sidRaw = up['id'];
      final scanId =
          sidRaw is int ? sidRaw : int.tryParse(sidRaw?.toString() ?? '');
      if (scanId == null) {
        throw NeuroscanApiException('Upload succeeded but no scan id returned.');
      }
      final rep = await NeuroscanApi.generateSegmentationReportFromPredictUpload(
        scanId: scanId,
        patientId: _patientId!,
        filesByModality: _filesMap(),
      );
      final pred = rep['prediction']?.toString() ?? '';
      final reportRaw = rep['report_id'];
      final reportId = reportRaw is int
          ? reportRaw
          : int.tryParse(reportRaw?.toString() ?? '');

      String? imgAbs;
      if (reportId != null) {
        try {
          final analysis = await NeuroscanApi.getAnalysis(reportId);
          final u = analysis['imageUrl']?.toString();
          if (u != null && u.isNotEmpty) {
            imgAbs = u.startsWith('http://') || u.startsWith('https://')
                ? NeuroscanApi.resolveMediaUrl(u)
                : NeuroscanApi.absoluteUrl(u);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = false;
        _outputImageUrl = imgAbs;
        _message = reportId != null
            ? 'Saved to database: report #$reportId. $pred'
            : 'Saved to database. $pred';
      });
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: 'Upload MRI Scan',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Upload MRI (BraTS modalities)',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: NeuroScanColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _showClinicSave
                        ? 'Doctors: upload four modalities, choose a patient, then use Save to clinic database '
                            '(MRI scan row + segmentation diagnosis + PDF report, same as the doctor dashboard). '
                            'Quick preview uses public POST /predict and does not write to the database.'
                        : 'Select four channels. Quick preview runs POST /predict (not saved). '
                            'Patients: use the Patient Dashboard ZIP upload to store scans for your doctor.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: NeuroScanColors.slate500,
                      height: 1.4,
                    ),
                  ),
                  if (_isPatient) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NeuroScanColors.blue50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NeuroScanColors.blue100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'To send MRI to your doctor, use Patient Dashboard and upload one .zip file (stored in the database).',
                            style: TextStyle(
                              fontSize: 13,
                              color: NeuroScanColors.slate700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.pushReplacementNamed(
                                      context,
                                      '/patient-dashboard',
                                    ),
                            child: const Text('Open Patient Dashboard'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_showClinicSave) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      // `value` tracks selection across rebuilds; `initialValue` is one-shot only.
                      value: _patientId, // ignore: deprecated_member_use
                      decoration: const InputDecoration(
                        labelText: 'Patient (database)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _patients)
                          if (_patientDropdownId(p) != null)
                            DropdownMenuItem<int>(
                              value: _patientDropdownId(p)!,
                              child: Text(
                                '${p['name'] ?? p['email'] ?? 'Patient'} (#${_patientDropdownId(p)})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _patientId = v),
                    ),
                    if (_patients.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No patient accounts found. Register a patient first.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),
                  for (final k in mriModalityKeys) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_labels[k]!),
                      subtitle: Text(
                        _files[k] == null
                            ? 'No file'
                            : (_files[k]!.name.isNotEmpty
                                ? _files[k]!.name
                                : (_files[k]!.path?.split(RegExp(r'[/\\]')).last ??
                                    'selected file')),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _busy ? null : () => _pick(k),
                        child: const Text('Browse'),
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(minHeight: 6),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _error
                            ? NeuroScanColors.red600
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                  if (_outputImageUrl != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _outputImageUrl!,
                        height: 220,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text(
                          'Could not load output image (check API base URL).',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_showClinicSave) ...[
                    FilledButton(
                      onPressed: _busy ? null : _runSaveToClinic,
                      child: const Text('Save to clinic database'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busy ? null : _runPredict,
                      child: const Text('Quick preview (no database)'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: _busy || _isPatient ? null : _runPredict,
                      child: const Text('Run segmentation (preview)'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
