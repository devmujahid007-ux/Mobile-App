import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/mri_modalities.dart';
import '../services/auth_storage.dart';
import '../services/neuroscan_api.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_shell.dart';

/// Matches web `UploadMRI.jsx`: four BraTS modalities → `POST /predict`.
/// Signed-in patients can also submit to the clinic (`POST /mri/upload` + `doctor_id`).
class UploadMRIScreen extends StatefulWidget {
  const UploadMRIScreen({super.key});

  @override
  State<UploadMRIScreen> createState() => _UploadMRIScreenState();
}

class _UploadMRIScreenState extends State<UploadMRIScreen> {
  final Map<String, String?> _paths = {
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
  List<Map<String, dynamic>> _doctors = [];
  int? _doctorId;
  bool _isPatient = false;

  @override
  void initState() {
    super.initState();
    _hydrateRole();
  }

  Future<void> _hydrateRole() async {
    final t = await AuthStorage.getToken();
    if (t == null || t.isEmpty) return;
    try {
      final me = await NeuroscanApi.me();
      final role = (me['role'] as String? ?? '').toLowerCase();
      if (role != 'patient') return;
      final docs = await NeuroscanApi.listDoctors();
      if (!mounted) return;
      setState(() {
        _isPatient = true;
        _doctors = docs.whereType<Map<String, dynamic>>().toList();
        if (_doctors.length == 1) {
          _doctorId = _doctors.first['id'] is int
              ? _doctors.first['id'] as int
              : int.tryParse('${_doctors.first['id']}');
        }
      });
    } catch (_) {
      /* guest or expired token */
    }
  }

  Future<void> _pick(String key) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['nii', 'gz', 'dcm', 'dicom'],
    );
    if (res == null || res.files.isEmpty) return;
    final p = res.files.single.path;
    setState(() {
      _paths[key] = p;
      _message = null;
      _outputImageUrl = null;
    });
  }

  bool _allSet() =>
      _paths.values.every((p) => p != null && p.isNotEmpty);

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
      final out = await NeuroscanApi.predictTumorSegmentation({
        for (final e in _paths.entries) e.key: e.value!,
      });
      final img = out['output_image']?.toString();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outputImageUrl =
            img != null ? NeuroscanApi.resolveMediaUrl(img) : null;
        _message = '${out['message'] ?? 'Done'}';
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

  Future<void> _uploadToClinic() async {
    if (!_isPatient) return;
    if (_doctorId == null || _doctorId! <= 0) {
      setState(() {
        _error = true;
        _message = 'Choose a doctor for this upload.';
      });
      return;
    }
    if (!_allSet()) {
      setState(() {
        _error = true;
        _message = 'Select all four MRI files first.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
      _message = null;
    });
    try {
      await NeuroscanApi.uploadMri(
        filePathsByModality: {for (final e in _paths.entries) e.key: e.value!},
        doctorId: _doctorId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message =
            'Upload sent to your doctor. Track status on the patient dashboard.';
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
                  const Text(
                    'Same flow as the web app: all four channels, then run the segmentation model (`POST /predict`). NIfTI preferred for `/predict` on the bundled backend.',
                    style: TextStyle(
                      fontSize: 14,
                      color: NeuroScanColors.slate500,
                    ),
                  ),
                  if (_isPatient && _doctors.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Assign to doctor (clinic upload)',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _doctorId,
                          isExpanded: true,
                          hint: const Text('Select doctor'),
                          items: [
                            for (final d in _doctors)
                              if ((d['id'] is int
                                      ? d['id'] as int
                                      : int.tryParse('${d['id']}')) !=
                                  null)
                                DropdownMenuItem<int>(
                                  value: d['id'] is int
                                      ? d['id'] as int
                                      : int.tryParse('${d['id']}')!,
                                  child: Text(
                                    '${d['name'] ?? d['email'] ?? 'Doctor'}',
                                  ),
                                ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _doctorId = v),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  for (final k in mriModalityKeys) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_labels[k]!),
                      subtitle: Text(
                        _paths[k] == null
                            ? 'No file'
                            : _paths[k]!.split(RegExp(r'[/\\]')).last,
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
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : _runPredict,
                          child: const Text('Run segmentation'),
                        ),
                      ),
                      if (_isPatient) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _uploadToClinic,
                            child: const Text('Send to doctor'),
                          ),
                        ),
                      ],
                    ],
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
