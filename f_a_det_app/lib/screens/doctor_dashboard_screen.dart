import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/mri_modalities.dart';
import '../services/auth_guard.dart';
import '../services/neuroscan_api.dart';
import '../services/patient_scan_zip.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_drawer.dart';
import '../widgets/neuroscan_shell.dart';

int? _parseId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}

bool _isValidMRIFile(PlatformFile? file) {
  if (file == null) return false;
  final name = (file.name).toLowerCase();
  const exts = ['.dcm', '.dicom', '.nii', '.nii.gz'];
  for (final e in exts) {
    if (name.endsWith(e)) return true;
  }
  return false;
}

class _MriPreviewDialog extends StatefulWidget {
  const _MriPreviewDialog({required this.scanId});
  final int scanId;

  @override
  State<_MriPreviewDialog> createState() => _MriPreviewDialogState();
}

class _MriPreviewDialogState extends State<_MriPreviewDialog> {
  bool _loadingMeta = true;
  bool _loadingImg = false;
  String? _error;
  int _depth = 1;
  int _slice = 0;
  int _defaultSlice = 0;
  MemoryImage? _img;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    setState(() {
      _loadingMeta = true;
      _error = null;
    });
    try {
      final meta = await NeuroscanApi.getMriPreviewMeta(widget.scanId);
      final d = _parseId(meta['depth']) ?? 1;
      final def = _parseId(meta['default_slice']) ?? 0;
      if (!mounted) return;
      setState(() {
        _depth = d <= 0 ? 1 : d;
        _defaultSlice = def.clamp(0, (d <= 0 ? 1 : d) - 1);
        _slice = _defaultSlice;
        _loadingMeta = false;
      });
      await _loadImage(_slice);
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingMeta = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingMeta = false;
      });
    }
  }

  Future<void> _loadImage(int slice) async {
    setState(() {
      _loadingImg = true;
      _error = null;
    });
    try {
      final bytes = await NeuroscanApi.fetchMriPreviewPng(
        widget.scanId,
        sliceIndex: slice,
      );
      if (!mounted) return;
      setState(() {
        _img = MemoryImage(bytes);
        _loadingImg = false;
      });
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingImg = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingImg = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('MRI viewer · Scan #${widget.scanId}'),
      content: SizedBox(
        width: 540,
        child: _loadingMeta
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: NeuroScanColors.red600),
                      ),
                    ),
                  Row(
                    children: [
                      const Text('Axial slice'),
                      const SizedBox(width: 8),
                      Text('$_slice / ${_depth - 1}'),
                      if (_loadingImg) ...[
                        const SizedBox(width: 8),
                        Text('Loading…', style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                      ],
                    ],
                  ),
                  Slider(
                    value: _slice.toDouble(),
                    min: 0,
                    max: (_depth - 1).toDouble(),
                    divisions: _depth > 1 ? _depth - 1 : 1,
                    onChanged: (v) => setState(() => _slice = v.round()),
                    onChangeEnd: (v) => _loadImage(v.round()),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 280,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: NeuroScanColors.slate700),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _loadingImg
                          ? const Center(child: CircularProgressIndicator())
                          : (_img == null
                              ? const Center(child: Text('No image', style: TextStyle(color: Colors.white70)))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image(
                                    image: _img!,
                                    fit: BoxFit.contain,
                                  ),
                                )),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Doctor workflow aligned with web `DoctorDashboardPage.jsx`.
class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  bool _loading = true;
  String? _error;
  String? _notice;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _reportList = [];
  Map<String, dynamic>? _me;
  bool _showMriSection = true;
  /// 0 = brain tumor (BraTS ZIP / modalities), 1 = Alzheimer (PNG pipeline).
  int _dashTab = 0;
  int? _tumorWorkflowScanId;
  int? _alzWorkflowScanId;
  Map<String, dynamic>? _modelView;
  int _resultImageTs = 0;
  bool _viewBusy = false;
  bool _generateBusy = false;
  bool _alzViewBusy = false;
  bool _downloadZipBusy = false;
  final Set<int> _sendingReports = {};
  final Map<String, PlatformFile?> _uploadFiles = {
    for (final k in mriModalityKeys) k: null,
  };
  PlatformFile? _alzUploadImage;

  /// Two-step report flow (web parity): draft text after first tap; PDF after second.
  int? _reportDraftReportId;
  int? _reportDraftScanId;
  bool _reportDraftIsAlzheimer = false;
  TextEditingController? _reportDraftFindings;
  TextEditingController? _reportDraftAnalysis;
  TextEditingController? _reportDraftProbs;

  bool _rowIsAlzheimer(Map<String, dynamic> r) =>
      '${r['scan_kind']}'.toLowerCase() == 'alzheimer';

  List<Map<String, dynamic>> _sentOrAnalyzed() => _requests.where((r) {
        final s = '${r['status']}'.toLowerCase();
        return s == 'sent' || s == 'analyzed';
      }).toList();

  List<Map<String, dynamic>> get _tumorWorkflowScans =>
      _sentOrAnalyzed().where((r) => !_rowIsAlzheimer(r)).toList();

  List<Map<String, dynamic>> get _alzWorkflowScans =>
      _sentOrAnalyzed().where(_rowIsAlzheimer).toList();

  /// At least one **sent** or **analyzed** tumor case (BraTS workflow).
  bool get _hasActiveWorkflowScan {
    final w = _tumorWorkflowScans;
    return w.isNotEmpty && _tumorWorkflowScanId != null;
  }

  /// PDF is generated only after a successful `/predict` on the same four local files.
  bool get _canGenerateClinicalPdf {
    if (!_hasActiveWorkflowScan) return false;
    if (_tumorWorkflowScanId == null) return false;
    if (_modelView == null) return false;
    if ((_modelView!['source']?.toString() ?? '') != 'local_predict') return false;
    return mriModalityKeys.every((k) => _uploadFiles[k] != null);
  }

  Map<String, dynamic>? get _selectedWorkflowScan {
    for (final r in _tumorWorkflowScans) {
      if (_parseId(r['id']) == _tumorWorkflowScanId) return r;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedAlzWorkflowScan {
    for (final r in _alzWorkflowScans) {
      if (_parseId(r['id']) == _alzWorkflowScanId) return r;
    }
    return null;
  }

  bool get _hasActiveAlzWorkflow =>
      _alzWorkflowScans.isNotEmpty && _alzWorkflowScanId != null;

  bool get _hasReportDraftForCurrentWorkflow {
    if (_reportDraftReportId == null || _reportDraftScanId == null) return false;
    if (_reportDraftIsAlzheimer != (_dashTab == 1)) return false;
    final cur = _dashTab == 0 ? _tumorWorkflowScanId : _alzWorkflowScanId;
    return cur != null && cur == _reportDraftScanId;
  }

  void _disposeReportDraft() {
    _reportDraftFindings?.dispose();
    _reportDraftAnalysis?.dispose();
    _reportDraftProbs?.dispose();
    _reportDraftFindings = null;
    _reportDraftAnalysis = null;
    _reportDraftProbs = null;
    _reportDraftReportId = null;
    _reportDraftScanId = null;
  }

  @override
  void dispose() {
    _disposeReportDraft();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await AuthGuard.redirectIfUnauthenticated(context);
      if (ok) await _load();
    });
  }

  void _syncWorkflowSelection() {
    void side(List<Map<String, dynamic>> w, void Function(int?) setId, int? Function() getId) {
      if (w.isEmpty) {
        setId(null);
        return;
      }
      final cur = getId();
      final exists = w.any((r) => _parseId(r['id']) == cur);
      if (cur == null || !exists) {
        setId(_parseId(w.first['id']));
      }
    }

    side(_tumorWorkflowScans, (v) => _tumorWorkflowScanId = v, () => _tumorWorkflowScanId);
    side(_alzWorkflowScans, (v) => _alzWorkflowScanId = v, () => _alzWorkflowScanId);
    final w = _tumorWorkflowScans;
    if (w.isEmpty) {
      _modelView = null;
    }
  }

  /// Backend sends per-label **voxel counts** for segmentation histograms (stored and /predict parity).
  String _formatProbCell(dynamic raw, String? source) {
    final s = source ?? '';
    if (raw == null) return '—';
    final n = raw is num ? raw : num.tryParse('$raw');
    if (n == null) return '$raw';
    if (s == 'stored_scan' || s == 'local_predict' || n.abs() > 100) {
      return '${n is int ? n : n.round()} vox';
    }
    return '${n is int ? n : n.toStringAsFixed(1)}%';
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final requestsRaw = await NeuroscanApi.getDoctorRequests();
      final me = await NeuroscanApi.me();
      List<Map<String, dynamic>> reports = [];
      try {
        final raw = await NeuroscanApi.listReports();
        reports = raw.whereType<Map<String, dynamic>>().toList();
      } catch (_) {
        reports = [];
      }
      final normalized = requestsRaw.whereType<Map<String, dynamic>>().toList();
      if (!mounted) return;
      setState(() {
        _requests = normalized;
        _reportList = reports;
        _me = me;
        _syncWorkflowSelection();
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

  int get _reportsSentCount =>
      _reportList.where((r) => r['sent_to_patient'] == true).length;

  String _patientLabel(Map<String, dynamic> scan) {
    final p = scan['patient'];
    if (p is Map) {
      return '${p['name'] ?? p['email'] ?? 'Patient'}';
    }
    return 'Patient';
  }

  String _fmtDate(dynamic raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _openPdfUrl(int reportId, {bool download = false, int? cacheBust}) async {
    final url = await NeuroscanApi.reportPdfOpenUrl(
      reportId,
      download: download,
      cacheBust: cacheBust,
    );
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText(url)),
      );
    }
  }

  Future<void> _downloadPatientScanZip() async {
    final id = _dashTab == 0 ? _tumorWorkflowScanId : _alzWorkflowScanId;
    if (id == null) {
      setState(() => _error = 'Select a patient scan first.');
      return;
    }
    var zipSavedOk = false;
    setState(() {
      _downloadZipBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      final got = await NeuroscanApi.downloadPatientScanBytes(id);
      final saved = await savePatientScanZip(got.bytes, got.filename);
      if (!mounted) return;
      if (saved != null) {
        zipSavedOk = true;
        if (kIsWeb) {
          setState(() {
            _error = null;
            _notice =
                'ZIP download started (${got.filename}). If no prompt appears, check the browser downloads bar or allow downloads for this site.';
          });
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saving ${got.filename}…')),
            );
          } catch (_) {}
        } else {
          setState(() {
            _error = null;
            _notice =
                'Patient scan saved as ZIP/volume:\n$saved\n\nOpen the file or re-upload modalities below after QC.';
          });
        }
      } else {
        setState(() => _error = 'Could not save the file on this device.');
      }
    } on NeuroscanApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && !zipSavedOk) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _downloadZipBusy = false;
          if (zipSavedOk) _error = null;
        });
      }
    }
  }

  void _onUploadPick(String modality, PlatformFile? picked) {
    if (picked == null) return;
    if (!_isValidMRIFile(picked)) {
      setState(() {
        _uploadFiles[modality] = null;
        _notice =
            'Unsupported format. Use DICOM (.dcm, .dicom) or NIfTI (.nii, .nii.gz).';
      });
      return;
    }
    if (_reportDraftReportId != null && !_reportDraftIsAlzheimer) {
      _disposeReportDraft();
    }
    setState(() {
      _uploadFiles[modality] = picked;
      _modelView = null;
      _notice = null;
      _error = null;
    });
  }

  void _clearUpload(String modality) {
    if (_reportDraftReportId != null && !_reportDraftIsAlzheimer) {
      _disposeReportDraft();
    }
    setState(() {
      _uploadFiles[modality] = null;
      _modelView = null;
      _notice = null;
    });
  }

  Future<void> _viewResultPredict() async {
    if (_reportDraftReportId != null && !_reportDraftIsAlzheimer) {
      _disposeReportDraft();
    }
    setState(() {
      _viewBusy = true;
      _error = null;
      _notice = null;
      _modelView = null;
    });
    try {
      if (!_hasActiveWorkflowScan) {
        throw NeuroscanApiException(
          'No active patient scan in your queue (status sent or analyzed). '
          'Wait for a patient to send a scan, then refresh — you cannot run View result without a pending case.',
        );
      }
      final ready = mriModalityKeys.every((k) => _uploadFiles[k] != null);
      if (!ready) {
        throw NeuroscanApiException('Please upload all 4 MRI scans (same pipeline as /predict).');
      }
      final data = await NeuroscanApi.predictTumorSegmentation({
        for (final e in _uploadFiles.entries) e.key: e.value!,
      });
      if (!mounted) return;
      final probs = data['probs'];
      setState(() {
        _modelView = {
          'prediction': data['message']?.toString() ?? 'Prediction completed',
          'confidence': data['confidence'],
          'probs': probs is Map ? Map<String, dynamic>.from(probs) : null,
          'tumor_volume': data['tumor_volume'],
          'output_image_url':
              data['output_image']?.toString() ?? data['output_image_url']?.toString(),
          'model_version': data['model_version']?.toString(),
          'source': 'local_predict',
        };
        _resultImageTs = DateTime.now().millisecondsSinceEpoch;
      });
    } on NeuroscanApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _viewBusy = false);
    }
  }

  Future<void> _generatePdfReport() async {
    final id = _dashTab == 0 ? _tumorWorkflowScanId : _alzWorkflowScanId;
    if (id == null) {
      setState(() => _error = 'Select which patient scan you are working on.');
      return;
    }
    final req = _dashTab == 0 ? _selectedWorkflowScan : _selectedAlzWorkflowScan;
    final patientId = _parseId(req?['patient_id']);
    if (req == null || patientId == null) {
      setState(() => _error = 'Could not resolve patient for this scan.');
      return;
    }
    final patient = req['patient'];
    final name = patient is Map ? patient['name']?.toString() : null;
    final age = patient is Map ? _parseId(patient['age']) : null;

    final finishingDraft =
        _hasReportDraftForCurrentWorkflow && _reportDraftReportId != null;

    setState(() {
      _generateBusy = true;
      _error = null;
      if (!finishingDraft) _notice = null;
    });
    try {
      if (finishingDraft) {
        final rid = _reportDraftReportId!;
        await NeuroscanApi.finalizeReportPdf(
          reportId: rid,
          findingsParagraph: _reportDraftFindings!.text,
          analysisParagraph: _reportDraftAnalysis!.text,
          probsParagraph: _reportDraftIsAlzheimer ? _reportDraftProbs!.text : null,
        );
        _disposeReportDraft();
        if (!mounted) return;
        setState(() {
          _modelView = null;
          _notice =
              'PDF saved on the server. Download opened — use report history to send to the patient when ready.';
        });
        await _load(quiet: true);
        if (mounted) {
          await _openPdfUrl(
            rid,
            download: true,
            cacheBust: DateTime.now().millisecondsSinceEpoch,
          );
        }
        return;
      }

      final useCurrent = _modelView != null;
      final res = await NeuroscanApi.generateSegmentationReport(
        scanId: id,
        patientId: patientId,
        patientName: name,
        age: age,
        gender: null,
        useCurrentResult: useCurrent,
        currentPrediction: useCurrent ? _modelView!['prediction']?.toString() : null,
        currentConfidence: useCurrent
            ? (_modelView!['confidence'] is num
                ? (_modelView!['confidence'] as num).toDouble()
                : double.tryParse('${_modelView!['confidence'] ?? ''}'))
            : null,
        currentTumorVolume: useCurrent ? _modelView!['tumor_volume']?.toString() : null,
        currentProbs: useCurrent && _modelView!['probs'] is Map
            ? Map<String, dynamic>.from(_modelView!['probs'] as Map)
            : null,
        currentOutputImageUrl: useCurrent ? _modelView!['output_image_url']?.toString() : null,
        currentModelVersion: useCurrent ? _modelView!['model_version']?.toString() : null,
        skipPdf: true,
      );
      final rid = _parseId(res['report_id']);
      if (!mounted) return;
      if (rid == null) {
        setState(() => _error = 'Report draft was created but the server did not return a report id.');
        return;
      }
      _disposeReportDraft();
      final isAlz = _dashTab == 1;
      setState(() {
        _reportDraftReportId = rid;
        _reportDraftScanId = id;
        _reportDraftIsAlzheimer = isAlz;
        _reportDraftFindings =
            TextEditingController(text: '${res['findings_paragraph'] ?? ''}');
        _reportDraftAnalysis =
            TextEditingController(text: '${res['analysis_paragraph'] ?? ''}');
        _reportDraftProbs = isAlz
            ? TextEditingController(text: '${res['probs_paragraph'] ?? ''}')
            : null;
        _notice =
            'Review and edit the report text below, then tap the same button again to build and download the PDF.';
      });
      await _load(quiet: true);
    } on NeuroscanApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _generateBusy = false);
    }
  }

  Widget _buildReportDraftCard() {
    if (!_hasReportDraftForCurrentWorkflow ||
        _reportDraftFindings == null ||
        _reportDraftAnalysis == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review report (editable)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Adjust wording below, then tap Download report (PDF).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reportDraftFindings,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Findings',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reportDraftAnalysis,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Analysis',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            if (_reportDraftIsAlzheimer && _reportDraftProbs != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reportDraftProbs,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Class probabilities (shown in PDF)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendReportToPatientRow(int reportId, int patientId) async {
    setState(() {
      _sendingReports.add(reportId);
      _error = null;
      _notice = null;
    });
    try {
      await NeuroscanApi.sendReportToPatient(reportId: reportId, patientId: patientId);
      if (!mounted) return;
      setState(() => _notice = 'Report #$reportId was sent to the patient.');
      await _load(quiet: true);
    } on NeuroscanApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sendingReports.remove(reportId));
    }
  }

  List<Map<String, dynamic>> _reportsForModule({required bool alzheimer}) {
    return _reportList.where((row) {
      final sid = _parseId(row['scan_id']);
      if (sid == null) return !alzheimer;
      Map<String, dynamic>? scan;
      for (final r in _requests) {
        if (_parseId(r['id']) == sid) {
          scan = r;
          break;
        }
      }
      if (scan == null) return !alzheimer;
      return alzheimer ? _rowIsAlzheimer(scan) : !_rowIsAlzheimer(scan);
    }).toList();
  }

  Widget _statCard(String title, String value, String? subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: NeuroScanColors.blue600.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: NeuroScanColors.blue600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, color: NeuroScanColors.slate500)),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: NeuroScanColors.slate800,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: NeuroScanColors.slate400),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _viewAlzheimerResultLocal() async {
    final id = _alzWorkflowScanId;
    if (id == null) {
      setState(() => _error = 'Select an Alzheimer case first.');
      return;
    }
    final file = _alzUploadImage;
    if (file == null) {
      setState(() => _error = 'Upload PNG/JPG image first.');
      return;
    }
    if (_reportDraftReportId != null && _reportDraftIsAlzheimer) {
      _disposeReportDraft();
    }
    setState(() {
      _alzViewBusy = true;
      _error = null;
      _notice = null;
      _modelView = null;
    });
    try {
      final data = await NeuroscanApi.viewAlzheimerLocalResult(
        scanId: id,
        imageFile: file,
      );
      if (!mounted) return;
      setState(() {
        _modelView = {
          'prediction': data['prediction']?.toString() ?? 'Analysis completed',
          'confidence': data['confidence'],
          'probs': data['probs'] is Map ? Map<String, dynamic>.from(data['probs'] as Map) : null,
          'output_image_url': data['output_image_url']?.toString(),
          'model_version': data['model_version']?.toString(),
          'source': 'live_alzheimer',
        };
        _resultImageTs = DateTime.now().millisecondsSinceEpoch;
        _notice = 'View result completed. You can now generate report (PDF).';
      });
    } on NeuroscanApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _alzViewBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tumorWf = _tumorWorkflowScans;
    final alzWf = _alzWorkflowScans;
    final workflow = _dashTab == 0 ? tumorWf : alzWf;
    final openCount = workflow.length;
    final tumorReportList = _reportsForModule(alzheimer: false);
    final alzReportList = _reportsForModule(alzheimer: true);

    return NeuroScanShell(
      title: 'Doctor Dashboard',
      authSlot: NeuroScanAuthSlot.account,
      additionalActions: [
        FilledButton.tonal(
          onPressed: () => setState(() => _showMriSection = !_showMriSection),
          child: Text(_showMriSection ? 'Hide upload' : 'Upload MRI'),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Tumor: upload four BraTS modalities and use View result. '
                    'Alzheimer: upload PNG/JPG and use View result. Then generate PDF and send to patient.',
                    style: const TextStyle(fontSize: 13, color: NeuroScanColors.slate600),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment<int>(
                          value: 0,
                          label: Text('Tumor requests'),
                          icon: Icon(Icons.biotech_outlined, size: 18),
                        ),
                        ButtonSegment<int>(
                          value: 1,
                          label: Text('Alzheimer requests'),
                          icon: Icon(Icons.psychology_alt_outlined, size: 18),
                        ),
                      ],
                      selected: {_dashTab},
                      onSelectionChanged: (s) => setState(() {
                        _dashTab = s.first;
                        _disposeReportDraft();
                      }),
                    ),
                  ),
                  if (_me != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Logged in as ${_me!['email'] ?? 'Doctor'} (Doctor ID ${_me!['id'] ?? '-'})',
                        style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate400),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'Open Requests',
                          '$openCount',
                          'Sent / analyzed and pending delivery',
                          Icons.schedule_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          'Reports Sent',
                          '$_reportsSentCount',
                          'Delivered to patients',
                          Icons.send_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _statCard(
                    'Total Cases',
                    '${_requests.length}',
                    'All assigned MRI scans',
                    Icons.folder_open_outlined,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NeuroScanColors.slate200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dashTab == 0 ? 'Tumor queue' : 'Alzheimer queue',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: NeuroScanColors.slate800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${workflow.length} assigned',
                          style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                        ),
                        const SizedBox(height: 8),
                        if (workflow.isEmpty)
                          Text(
                            _dashTab == 0 ? 'No tumor requests yet.' : 'No Alzheimer requests yet.',
                            style: const TextStyle(color: NeuroScanColors.slate500),
                          )
                        else
                          ...workflow.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Scan #${r['id']} · ${_patientLabel(r)} · ${r['status']} · ${r['file_name'] ?? 'MRI'}',
                                style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate700),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                    ),
                  ],
                  if (_showMriSection && _dashTab == 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: NeuroScanColors.slate200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'MRI — view model output & report',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: NeuroScanColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Patient scan (open request)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NeuroScanColors.slate700),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            initialValue: _tumorWorkflowScanId,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            hint: const Text('No active scans (sent / analyzed)'),
                            items: tumorWf
                                .map(
                                  (r) => DropdownMenuItem<int>(
                                    value: _parseId(r['id']),
                                    child: Text(
                                      'Scan #${r['id']} — ${r['status']} — ${_patientLabel(r)} — ${r['file_name'] ?? 'MRI'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: tumorWf.isEmpty
                                ? null
                                : (v) => setState(() {
                                      _tumorWorkflowScanId = v;
                                      _modelView = null;
                                      if (_reportDraftReportId != null &&
                                          !_reportDraftIsAlzheimer &&
                                          v != _reportDraftScanId) {
                                        _disposeReportDraft();
                                      }
                                    }),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _downloadZipBusy ||
                                    tumorWf.isEmpty ||
                                    _tumorWorkflowScanId == null
                                ? null
                                : _downloadPatientScanZip,
                            icon: _downloadZipBusy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.folder_zip_outlined),
                            label: Text(_downloadZipBusy ? 'Preparing ZIP…' : 'Download MRI to this device'),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Uses the same file(s) the patient sent. Multi-file scans are bundled into one ZIP.',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(color: NeuroScanColors.slate300, style: BorderStyle.solid),
                              borderRadius: BorderRadius.circular(12),
                              color: NeuroScanColors.slate50.withValues(alpha: 0.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Four BraTS modalities',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: NeuroScanColors.slate800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Upload NIfTI (.nii/.nii.gz) files for t1c, t1n, t2f, t2w. '
                                  'Use View result first, then Generate report (PDF).',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                                if (tumorWf.isEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amber.shade200),
                                    ),
                                    child: Text(
                                      'No pending cases (sent or analyzed). View result and modality uploads stay '
                                      'disabled until a patient sends you a scan. Refresh after a new request arrives.',
                                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                ...mriModalityKeys.map((modality) {
                                  final label = mriModalityLabels[modality] ?? modality.toUpperCase();
                                  final f = _uploadFiles[modality];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                label,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                  color: NeuroScanColors.slate700,
                                                ),
                                              ),
                                              Text(
                                                f == null
                                                    ? 'No file selected'
                                                    : (f.name.isNotEmpty ? f.name : 'selected file'),
                                                style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: !_hasActiveWorkflowScan
                                              ? null
                                              : () async {
                                                  final res = await FilePicker.platform.pickFiles(
                                                    type: FileType.custom,
                                                    allowedExtensions: const ['nii', 'gz', 'dcm', 'dicom'],
                                                    withData: true,
                                                  );
                                                  if (res != null && res.files.isNotEmpty) {
                                                    _onUploadPick(modality, res.files.single);
                                                  }
                                                },
                                          child: const Text('Choose'),
                                        ),
                                        if (f != null)
                                          TextButton(
                                            onPressed:
                                                !_hasActiveWorkflowScan ? null : () => _clearUpload(modality),
                                            child: const Text('Clear'),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.indigo.shade700,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  onPressed: _viewBusy ||
                                          !_hasActiveWorkflowScan ||
                                          mriModalityKeys.any((m) => _uploadFiles[m] == null)
                                      ? null
                                      : _viewResultPredict,
                                  child: _viewBusy
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text('View result'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  onPressed: _generateBusy ||
                                          _tumorWorkflowScanId == null ||
                                          tumorWf.isEmpty ||
                                          (!_hasReportDraftForCurrentWorkflow && !_canGenerateClinicalPdf)
                                      ? null
                                      : _generatePdfReport,
                                  child: _generateBusy
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(
                                          _hasReportDraftForCurrentWorkflow
                                              ? 'Download report (PDF)'
                                              : 'Generate report (PDF)',
                                        ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'View result stays disabled until there is a pending patient case (sent or analyzed) '
                              'and all four modalities are chosen. Generate report stays disabled until View result '
                              'succeeds. First tap prepares editable text; second tap builds and downloads the PDF.',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                          ),
                          _buildReportDraftCard(),
                          if (_modelView != null) ...[
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: NeuroScanColors.slate50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: NeuroScanColors.slate200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: ColoredBox(
                                            color: Colors.black,
                                            child: (_modelView!['output_image_url'] != null)
                                                ? Image.network(
                                                    '${NeuroscanApi.resolveMediaUrl(NeuroscanApi.absoluteUrl(_modelView!['output_image_url']!.toString()))}?t=$_resultImageTs',
                                                    height: 200,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (_, __, ___) => const Padding(
                                                      padding: EdgeInsets.all(16),
                                                      child: Text(
                                                        'Could not load model image.',
                                                        style: TextStyle(color: Colors.white70),
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox(
                                                    height: 120,
                                                    child: Center(
                                                      child: Text('No preview image', style: TextStyle(color: Colors.white54)),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Prediction',
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                            ),
                                            Text(
                                              '${_modelView!['prediction']}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: NeuroScanColors.slate900,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Confidence',
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                            ),
                                            Text(
                                              _modelView!['confidence'] != null
                                                  ? '${_modelView!['confidence']}%'
                                                  : 'N/A',
                                            ),
                                            if (_modelView!['model_version'] != null &&
                                                '${_modelView!['model_version']}'.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                '${_modelView!['model_version']}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                              ),
                                            ],
                                            if (_modelView!['tumor_volume'] != null)
                                              Text('Tumor volume: ${_modelView!['tumor_volume']}'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_modelView!['probs'] != null &&
                                      (_modelView!['probs'] as Map).isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      (_modelView!['source']?.toString() ?? '') == 'local_predict'
                                          ? 'Label voxel counts (/predict)'
                                          : 'Label voxel counts (preview)',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                    ),
                                    ...Map<String, dynamic>.from(_modelView!['probs'] as Map)
                                        .entries
                                        .map(
                                          (e) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(e.key, style: const TextStyle(fontSize: 12)),
                                                Text(
                                                  _formatProbCell(
                                                    e.value,
                                                    _modelView!['source']?.toString(),
                                                  ),
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          const Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Report history',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: NeuroScanColors.slate900),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${tumorReportList.length} saved on server · PDFs via GET /reports',
                            style: const TextStyle(fontSize: 11, color: NeuroScanColors.slate500),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Download saves the file. Send to patient exposes the report on the patient dashboard.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          if (tumorReportList.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: NeuroScanColors.slate50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: NeuroScanColors.slate100),
                              ),
                              child: const Text(
                                'No reports yet. Run View result (/predict), then Generate report — review text, then tap again to download the PDF.',
                                style: TextStyle(fontSize: 13, color: NeuroScanColors.slate500),
                              ),
                            )
                          else
                            ...tumorReportList.map((row) {
                              final rid = _parseId(row['id']) ?? 0;
                              final pid = _parseId(row['patient_id']) ?? 0;
                              final sid = _parseId(row['scan_id']) ?? 0;
                              final sent = row['sent_to_patient'] == true;
                              final pname = row['patient_name']?.toString() ?? 'Patient #$pid';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(pname, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Report #$rid · Scan #$sid · ${_fmtDate(row['created_at'])}',
                                        style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: sent ? Colors.green.shade100 : Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            child: Text(
                                              sent ? 'Sent to patient' : 'Not sent yet',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: sent ? Colors.green.shade900 : Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton(
                                            onPressed: rid > 0
                                                ? () => Navigator.pushNamed(
                                                      context,
                                                      '/results',
                                                      arguments: {'id': rid},
                                                    )
                                                : null,
                                            child: const Text('View result summary'),
                                          ),
                                          OutlinedButton(
                                            onPressed: rid > 0 ? () => _openPdfUrl(rid, download: true) : null,
                                            child: const Text('Download'),
                                          ),
                                          if (!sent && rid > 0 && pid > 0)
                                            FilledButton(
                                              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                                              onPressed: _sendingReports.contains(rid)
                                                  ? null
                                                  : () => _sendReportToPatientRow(rid, pid),
                                              child: _sendingReports.contains(rid)
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                    )
                                                  : const Text('Send to patient'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                  if (_showMriSection && _dashTab == 1) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: NeuroScanColors.slate200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Alzheimer — view model output & report',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: NeuroScanColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Upload PNG/JPG and run View result (same flow as web), then generate report.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Patient scan (Alzheimer request)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NeuroScanColors.slate700),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            initialValue: _alzWorkflowScanId,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            hint: const Text('No Alzheimer scans (sent / analyzed)'),
                            items: alzWf
                                .map(
                                  (r) => DropdownMenuItem<int>(
                                    value: _parseId(r['id']),
                                    child: Text(
                                      'Scan #${r['id']} — ${r['status']} — ${_patientLabel(r)} — ${r['file_name'] ?? 'MRI'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: alzWf.isEmpty
                                ? null
                                : (v) => setState(() {
                                      _alzWorkflowScanId = v;
                                      if (_reportDraftReportId != null &&
                                          _reportDraftIsAlzheimer &&
                                          v != _reportDraftScanId) {
                                        _disposeReportDraft();
                                      }
                                    }),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _downloadZipBusy || alzWf.isEmpty || _alzWorkflowScanId == null
                                ? null
                                : _downloadPatientScanZip,
                            icon: _downloadZipBusy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.download_outlined),
                            label: Text(_downloadZipBusy ? 'Preparing…' : 'Download MRI image'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _hasActiveAlzWorkflow
                                ? () async {
                                    final res = await FilePicker.platform.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: const ['png', 'jpg', 'jpeg'],
                                      withData: true,
                                    );
                                    if (res != null && res.files.isNotEmpty) {
                                      if (_reportDraftReportId != null && _reportDraftIsAlzheimer) {
                                        _disposeReportDraft();
                                      }
                                      setState(() {
                                        _alzUploadImage = res.files.single;
                                        _modelView = null;
                                      });
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(
                              _alzUploadImage == null
                                  ? 'Choose PNG/JPG'
                                  : (_alzUploadImage!.name.isNotEmpty
                                      ? _alzUploadImage!.name
                                      : 'Image selected'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _alzViewBusy || !_hasActiveAlzWorkflow ? null : _viewAlzheimerResultLocal,
                            icon: _alzViewBusy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.analytics_outlined),
                            label: Text(_alzViewBusy ? 'Running model…' : 'View result'),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _generateBusy ||
                                    _alzWorkflowScanId == null ||
                                    (!_hasReportDraftForCurrentWorkflow &&
                                        (_modelView == null ||
                                            _modelView!['source']?.toString() != 'live_alzheimer'))
                                ? null
                                : _generatePdfReport,
                            child: _generateBusy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(
                                    _hasReportDraftForCurrentWorkflow
                                        ? 'Download report (PDF)'
                                        : 'Generate report (PDF)',
                                  ),
                          ),
                          _buildReportDraftCard(),
                          if (_selectedAlzWorkflowScan?['diagnosis'] != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: NeuroScanColors.slate50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: NeuroScanColors.slate200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Latest analysis', style: TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${(_selectedAlzWorkflowScan!['diagnosis'] as Map)['prediction'] ?? '—'} · '
                                    '${(_selectedAlzWorkflowScan!['diagnosis'] as Map)['confidence'] ?? '—'}% confidence',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_modelView != null &&
                              (_modelView!['source']?.toString() == 'live_alzheimer')) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: NeuroScanColors.slate50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: NeuroScanColors.slate200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 12,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: ColoredBox(
                                            color: Colors.black,
                                            child: (_modelView!['output_image_url'] != null)
                                                ? Image.network(
                                                    '${NeuroscanApi.resolveMediaUrl(NeuroscanApi.absoluteUrl(_modelView!['output_image_url']!.toString()))}?t=$_resultImageTs',
                                                    height: 220,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (_, __, ___) => const SizedBox(
                                                      height: 220,
                                                      child: Center(
                                                        child: Text(
                                                          'Could not load model image.',
                                                          style: TextStyle(color: Colors.white70),
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox(
                                                    height: 220,
                                                    child: Center(
                                                      child: Text(
                                                        'No image',
                                                        style: TextStyle(color: Colors.white70),
                                                      ),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 10,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'PREDICTION',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            Text(
                                              '${_modelView!['prediction'] ?? '—'}',
                                              style: const TextStyle(
                                                fontSize: 28,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'CONFIDENCE',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            Text(
                                              () {
                                                final c = _modelView!['confidence'];
                                                final n = c is num ? c.toDouble() : double.tryParse('$c');
                                                if (n == null) return '—';
                                                final p = n <= 1 ? n * 100 : n;
                                                return '${p.toStringAsFixed(1)}%';
                                              }(),
                                              style: const TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (_modelView!['model_version'] != null &&
                                                '${_modelView!['model_version']}'.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                '${_modelView!['model_version']}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_modelView!['probs'] is Map &&
                                      (_modelView!['probs'] as Map).isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: NeuroScanColors.slate200),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Class -> estimated %',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                          const SizedBox(height: 6),
                                          ...Map<String, dynamic>.from(_modelView!['probs'] as Map)
                                              .entries
                                              .map(
                                                (e) {
                                                  final n = e.value is num
                                                      ? (e.value as num).toDouble()
                                                      : double.tryParse('${e.value}');
                                                  final pct = n == null ? '—' : '${(n <= 1 ? n * 100 : n).toStringAsFixed(1)}%';
                                                  return Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Text(e.key, style: const TextStyle(fontSize: 13)),
                                                        Text(pct, style: const TextStyle(fontSize: 13)),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          const Text(
                            'Report history',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: NeuroScanColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${alzReportList.length} saved on server · PDFs via GET /reports',
                            style: const TextStyle(fontSize: 11, color: NeuroScanColors.slate500),
                          ),
                          const SizedBox(height: 10),
                          if (alzReportList.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: NeuroScanColors.slate50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: NeuroScanColors.slate100),
                              ),
                              child: const Text(
                                'No Alzheimer reports yet. Run View result, then Generate report — review text, then tap again to download the PDF.',
                                style: TextStyle(fontSize: 13, color: NeuroScanColors.slate500),
                              ),
                            )
                          else
                            ...alzReportList.map((row) {
                              final rid = _parseId(row['id']) ?? 0;
                              final pid = _parseId(row['patient_id']) ?? 0;
                              final sid = _parseId(row['scan_id']) ?? 0;
                              final sent = row['sent_to_patient'] == true;
                              final pname = row['patient_name']?.toString() ?? 'Patient #$pid';
                              return Card(
                                margin: const EdgeInsets.only(top: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(pname, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Report #$rid · Scan #$sid · ${_fmtDate(row['created_at'])}',
                                        style: const TextStyle(fontSize: 12, color: NeuroScanColors.slate500),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton(
                                            onPressed: rid > 0
                                                ? () => Navigator.pushNamed(
                                                      context,
                                                      '/results',
                                                      arguments: {'id': rid},
                                                    )
                                                : null,
                                            child: const Text('View result summary'),
                                          ),
                                          OutlinedButton(
                                            onPressed: rid > 0 ? () => _openPdfUrl(rid, download: true) : null,
                                            child: const Text('Download'),
                                          ),
                                          if (!sent && rid > 0 && pid > 0)
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Colors.green.shade700,
                                              ),
                                              onPressed: _sendingReports.contains(rid)
                                                  ? null
                                                  : () => _sendReportToPatientRow(rid, pid),
                                              child: _sendingReports.contains(rid)
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : const Text('Send to patient'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    Text(_notice!, style: TextStyle(color: Colors.green.shade800)),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
