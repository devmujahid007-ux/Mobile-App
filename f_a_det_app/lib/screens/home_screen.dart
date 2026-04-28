import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../services/analyses_sse.dart';
import '../services/neuroscan_api.dart';
import '../services/neuroscan_api_config.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/neuroscan_footer.dart';

/// ---------------- How it works (defaults until /data/Home.json loads) ----------------
class HowItWorksStep {
  final int step;
  final String title;
  final String desc;

  const HowItWorksStep(
      {required this.step, required this.title, required this.desc});

  factory HowItWorksStep.fromJson(Map<String, dynamic> j) => HowItWorksStep(
        step: (j['step'] ?? 0) is int
            ? j['step']
            : int.tryParse('${j['step']}') ?? 0,
        title: (j['title'] ?? '').toString(),
        desc: (j['desc'] ?? '').toString(),
      );
}

class RecentAnalysis {
  final String id;
  /// Set when backend exposes a numeric report id (`GET /api/analyses/{id}`).
  final int? reportId;
  final String? image; // asset or network path
  /// Inline bitmap from `GET /api/analyses/recent` (`thumbnailDataUrl`) — preferred on Flutter web.
  final Uint8List? thumbnailBytes;
  final String prediction;
  final num confidence;
  final String patientLabel;
  final String timeLabel;
  /// Relative path from API (`viewUrl`), e.g. `/results/12`.
  final String viewPath;
  final String downloadUrl;

  const RecentAnalysis({
    required this.id,
    this.reportId,
    this.image,
    this.thumbnailBytes,
    required this.prediction,
    required this.confidence,
    required this.patientLabel,
    required this.timeLabel,
    required this.viewPath,
    required this.downloadUrl,
  });

  factory RecentAnalysis.fromBackend(Map<String, dynamic> j) {
    final idRaw = j['id'];
    int? rid;
    if (j['report_id'] != null) {
      rid = int.tryParse('${j['report_id']}');
    }
    if (rid == null) {
      if (idRaw is int) {
        rid = idRaw;
      } else if (idRaw is String && !idRaw.trim().toUpperCase().startsWith('D-')) {
        rid = int.tryParse(idRaw.trim());
      }
    }
    final vPath = j['viewUrl']?.toString();
    if (rid == null && vPath != null && vPath.isNotEmpty) {
      final m = RegExp(r'/results/(\d+)').firstMatch(vPath);
      if (m != null) {
        rid = int.tryParse(m.group(1)!);
      }
    }
    final patient = j['patient'];
    var patientLabel = 'MRI Study';
    if (patient is Map) {
      final n = patient['name'] ?? patient['email'] ?? 'Patient';
      final fn = j['fileName'] ?? j['file_name'] ?? 'scan';
      patientLabel = '$n · $fn';
    }
    final doctor = j['doctor'];
    if (doctor is Map && (doctor['name'] != null || doctor['email'] != null)) {
      final d = '${doctor['name'] ?? doctor['email']}';
      if (d.isNotEmpty) {
        patientLabel = '$patientLabel · Dr $d';
      }
    }
    DateTime? dt;
    try {
      dt = DateTime.tryParse('${j['date'] ?? ''}');
    } catch (_) {}
    final fmt = DateFormat.yMMMd().add_jm();
    num conf = j['confidence'] is num
        ? j['confidence'] as num
        : num.tryParse('${j['confidence']}') ?? 0;
    // Stored as mean probability (0–1) from segmentation; show as % on home.
    if (conf > 0 && conf <= 1) {
      conf = conf * 100;
    }
    var imgPath = j['imageUrl']?.toString() ?? j['image']?.toString();
    if ((imgPath == null || imgPath.isEmpty) && j['segmentation'] is Map) {
      final seg = Map<String, dynamic>.from(j['segmentation'] as Map);
      imgPath = seg['overlay_image']?.toString() ??
          seg['reference_mri_png']?.toString();
    }
    if (imgPath == null || imgPath.isEmpty) {
      imgPath = j['output_image_url']?.toString();
    }
    String? imageAbs;
    if (imgPath != null && imgPath.isNotEmpty) {
      imageAbs = imgPath.startsWith('http://') || imgPath.startsWith('https://')
          ? NeuroscanApi.resolveMediaUrl(imgPath)
          : NeuroscanApi.absoluteUrl(imgPath);
    }
    Uint8List? thumbBytes;
    final tdu = j['thumbnailDataUrl']?.toString();
    if (tdu != null && tdu.startsWith('data:image')) {
      final comma = tdu.indexOf(',');
      if (comma >= 0) {
        try {
          thumbBytes = base64Decode(tdu.substring(comma + 1));
        } catch (_) {}
      }
    }
    final dlRaw =
        j['downloadUrl']?.toString() ?? j['reportDownloadUrl']?.toString();
    return RecentAnalysis(
      id: '${j['diagnosis_id'] ?? idRaw}',
      reportId: rid,
      image: imageAbs,
      thumbnailBytes: thumbBytes,
      prediction: '${j['prediction'] ?? j['label'] ?? ''}',
      confidence: conf,
      patientLabel: patientLabel,
      timeLabel: dt != null ? fmt.format(dt.toLocal()) : '—',
      viewPath: (vPath != null && vPath.isNotEmpty) ? vPath : '/results',
      downloadUrl: NeuroscanApi.absoluteUrl(dlRaw),
    );
  }
}

const _mockHomeSteps = <HowItWorksStep>[
  HowItWorksStep(
      step: 1,
      title: 'Patient Upload (ZIP MRI)',
      desc:
          'Patient uploads MRI ZIP and assigns a doctor; scan appears in doctor workflow.'),
  HowItWorksStep(
      step: 2,
      title: 'Doctor Analysis + Report',
      desc:
          'Doctor reviews scan, runs analysis, and generates the report PDF on the server.'),
  HowItWorksStep(
      step: 3,
      title: 'Send + Patient Download',
      desc:
          'Doctor sends report to patient dashboard, and patient downloads the final PDF.'),
];


/// ---------------- WIDGETS ----------------

class FeatureCard extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  const FeatureCard(
      {super.key, required this.title, required this.desc, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NeuroScanColors.slate200),
        boxShadow: kElevationToShadow[1],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: NeuroScanColors.blue50,
                borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Icon(icon, color: NeuroScanColors.blue600, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: NeuroScanColors.slate800)),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: const TextStyle(
                      fontSize: 13, color: NeuroScanColors.slate500),
                  softWrap: true,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<HowItWorksStep> _howItWorks = List.of(_mockHomeSteps);

  List<RecentAnalysis> _recent = [];
  bool _loadingRecent = true;
  String? _errorRecent;

  Timer? _pollTimer;
  void Function()? _closeSse;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    if (kIsWeb) {
      _closeSse = openAnalysesSse(
        NeuroscanApi.absoluteUrl('/api/analyses/stream'),
        _onSsePayload,
        _ensurePolling,
      );
    } else {
      _ensurePolling();
    }
    _hydrateMeta();
  }

  @override
  void dispose() {
    try {
      _closeSse?.call();
    } catch (_) {}
    _closeSse = null;
    _pollTimer?.cancel();
    super.dispose();
  }

  void _ensurePolling() {
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadRecent(),
    );
  }

  void _onSsePayload(Map<String, dynamic> payload) {
    final t = payload['type']?.toString();
    if (t == 'analysis.created' && payload['analysis'] is Map) {
      final row = Map<String, dynamic>.from(payload['analysis'] as Map);
      final item = RecentAnalysis.fromBackend(row);
      if (!mounted) return;
      setState(() {
        final next = [item, ..._recent];
        final seen = <String>{};
        _recent = next
            .where((a) {
              if (seen.contains(a.id)) return false;
              seen.add(a.id);
              return true;
            })
            .take(6)
            .toList();
      });
    } else if (t == 'analysis.updated' && payload['analysis'] is Map) {
      final row = Map<String, dynamic>.from(payload['analysis'] as Map);
      final updated = RecentAnalysis.fromBackend(row);
      if (!mounted) return;
      setState(() {
        _recent = _recent
            .map((a) => a.id == updated.id ? updated : a)
            .toList();
      });
    }
  }

  // ---------- HELPERS ----------
  num _clampPct(num n) {
    if (n.isNaN) return 0;
    if (n < 0) return 0;
    if (n > 100) return 100;
    return n;
  }

  bool _isJson(http.Response res) {
    final ct = res.headers['content-type'] ?? '';
    return ct.toLowerCase().contains('application/json');
  }

  // ---------- FETCH (LIVE) ----------
  Future<void> _loadRecent() async {
    setState(() {
      _loadingRecent = true;
      _errorRecent = null;
    });

    try {
      final decoded = await NeuroscanApi.getRecentAnalyses(limit: 6);
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .map(RecentAnalysis.fromBackend)
          .take(6)
          .toList();
      if (!mounted) return;
      setState(() {
        _recent = list;
        _loadingRecent = false;
        _errorRecent = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recent = const [];
        _loadingRecent = false;
        _errorRecent =
            'Live feed unavailable right now. Upload a scan to generate new entries.';
      });
    }
  }

  // OPTIONAL: hydrate meta from /data/Home.json safely
  Future<void> _hydrateMeta() async {
    try {
      final res = await http
          .get(Uri.parse('${NeuroscanApiConfig.baseUrl}/data/Home.json'));
      if (res.statusCode >= 200 && res.statusCode < 300 && _isJson(res)) {
        final j = json.decode(res.body);
        if (j is Map<String, dynamic>) {
          if (j['howItWorksSteps'] is List) {
            final steps = (j['howItWorksSteps'] as List)
                .whereType<Map<String, dynamic>>()
                .map((e) => HowItWorksStep.fromJson(e))
                .toList();
            if (mounted && steps.isNotEmpty) {
              setState(() => _howItWorks = steps);
            }
          }
        }
      }
    } catch (_) {
      // keep mocks silently
    }
  }

  Widget _assetImg(String assetPath,
      {double? width, double? height, BoxFit? fit, BorderRadius? radius}) {
    final img = Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      ),
    );
    if (radius != null) {
      return ClipRRect(borderRadius: radius, child: img);
    }
    return img;
  }

  /// Load as network image unless the path is clearly a volume (NIfTI/DICOM), not a bitmap.
  static bool _shouldLoadNetworkImageThumb(String url) {
    final u = url.trim();
    if (u.isEmpty) return false;
    final uri = Uri.tryParse(u.startsWith('http') ? u : NeuroscanApi.absoluteUrl(u));
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.nii') ||
        path.endsWith('.nii.gz') ||
        path.endsWith('.dcm') ||
        path.endsWith('.dicom') ||
        path.endsWith('.zip')) {
      return false;
    }
    if (path.contains('/outputs/')) return true;
    if (path.contains('/uploads/results/')) return true;
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif');
  }

  Widget _thumbPlaceholder({double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }

  /// Recent-analysis thumbnails only: API URLs / data URLs / in-memory previews — never local mock assets.
  Widget _thumbImage(String? path,
      {Uint8List? thumbnailBytes,
      double? width,
      double? height,
      BoxFit? fit,
      BorderRadius? radius}) {
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      final mem = Image.memory(
        thumbnailBytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            _thumbPlaceholder(width: width, height: height),
      );
      if (radius != null) {
        return ClipRRect(borderRadius: radius, child: mem);
      }
      return mem;
    }

    final p = (path ?? '').trim();
    String? networkUrl;
    if (p.startsWith('http://') || p.startsWith('https://')) {
      networkUrl = NeuroscanApi.resolveMediaUrl(p);
    } else if (p.startsWith('/')) {
      final abs = NeuroscanApi.absoluteUrl(p);
      if (abs.startsWith('http://') || abs.startsWith('https://')) {
        networkUrl = abs;
      }
    }

    final Widget child;
    if (networkUrl != null && _shouldLoadNetworkImageThumb(networkUrl)) {
      child = Image.network(
        networkUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            _thumbPlaceholder(width: width, height: height),
      );
    } else {
      child = _thumbPlaceholder(width: width, height: height);
    }

    if (radius != null) {
      return ClipRRect(borderRadius: radius, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final first = _recent.isNotEmpty ? _recent.first : null;

    return AppScaffold(
      title: 'NeuroScan',
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [NeuroScanColors.blue50, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadRecent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // ---------------- Hero ----------------
              LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth >= 880;
                  final heroText = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _assetImg('assests/images/logo.png',
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                              radius: BorderRadius.circular(8)),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('NeuroScan',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: NeuroScanColors.slate900)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Clinical-ready MRI workflow for Brain Tumor and Alzheimer’s reporting',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                            color: NeuroScanColors.slate900),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'From patient uploads to doctor review and PDF delivery, NeuroScan provides a single workflow for analysis, reporting, and secure handoff between care teams and patients.',
                        style: TextStyle(
                            color: NeuroScanColors.slate600,
                            fontSize: 15,
                            height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: NeuroScanColors.slate200),
                              foregroundColor: NeuroScanColors.slate700,
                            ),
                            onPressed: () =>
                                Navigator.pushNamed(context, '/about'),
                            child: const Text('Open Platform'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '- Role-based dashboards for patients, doctors, and administrators',
                            style: TextStyle(
                                fontSize: 12,
                                color: NeuroScanColors.slate600),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '- Report lifecycle from scan upload to doctor delivery to patient download',
                            style: TextStyle(
                                fontSize: 12,
                                color: NeuroScanColors.slate600),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '- Secure APIs with JWT authentication and audit-friendly data flows',
                            style: TextStyle(
                                fontSize: 12,
                                color: NeuroScanColors.slate600),
                          ),
                        ],
                      ),
                    ],
                  );
                  final heroVisual = Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: kElevationToShadow[2],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _assetImg(
                          'assests/images/heroMRI.jpg',
                          height: isWide ? 384 : 288,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (!_loadingRecent && first != null)
                        Positioned(
                          right: 24,
                          bottom: -24,
                          child: Container(
                            width: 256,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: kElevationToShadow[2],
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _thumbImage(
                                    first.image,
                                    thumbnailBytes: first.thumbnailBytes,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Latest analysis',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                      Text(
                                        '${first.prediction} — ${_clampPct(first.confidence)}% confidence',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: heroText),
                        const SizedBox(width: 16),
                        Expanded(child: heroVisual),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heroText,
                      const SizedBox(height: 16),
                      heroVisual,
                    ],
                  );
                },
              ),

              const SizedBox(height: 48),

              // ---------------- Features ----------------
              const Text('Core Capabilities',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: NeuroScanColors.slate900)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth >= 880;
                  return GridView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 3 : 1,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      // Tall enough for icon row + multi-line copy (was 3.2 → bottom overflow).
                      childAspectRatio: isWide ? 2.05 : 1.72,
                    ),
                    children: const [
                      FeatureCard(
                        title: 'Patient-to-Doctor Intake',
                        desc:
                            'Patients upload ZIP MRI studies and assign doctors directly, preventing unassigned cases.',
                        icon: Icons.add,
                      ),
                      FeatureCard(
                        title: 'Doctor Review and Reporting',
                        desc:
                            'Doctors process scans, generate report PDFs, and send finalized reports to patient dashboards.',
                        icon: Icons.lock_outline,
                      ),
                      FeatureCard(
                        title: 'Admin Operations',
                        desc:
                            'Admins manage doctor/patient accounts, monitor platform usage, and maintain clean user lists.',
                        icon: Icons.picture_as_pdf_outlined,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // ---------------- How it works ----------------
              const Text('How The Workflow Runs',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: NeuroScanColors.slate900)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth >= 880;
                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 3 : 1,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isWide ? 1.82 : 1.52,
                    ),
                    itemCount: _howItWorks.length,
                    itemBuilder: (context, i) {
                      final s = _howItWorks[i];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: NeuroScanColors.slate200),
                          boxShadow: kElevationToShadow[1],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              alignment: Alignment.center,
                              child: Text('${s.step}',
                                  style: const TextStyle(
                                      color: NeuroScanColors.blue600,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 10),
                            Text(s.title,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: NeuroScanColors.slate800)),
                            const SizedBox(height: 6),
                            Text(
                              s.desc,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: NeuroScanColors.slate500),
                              softWrap: true,
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 48),

              // ---------------- Recent Analyses (NeuroScanAi Home.jsx parity) ----------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Analyses',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: NeuroScanColors.slate900,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/results'),
                    child: const Text(
                      'Sign in to view dashboards',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: NeuroScanColors.blue600,
                      ),
                    ),
                  ),
                ],
              ),
              if (_loadingRecent)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Loading recent analyses...',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ),
              if (!_loadingRecent && _errorRecent != null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    _errorRecent!,
                    style: TextStyle(color: Colors.red.shade600, fontSize: 14),
                  ),
                ),
              if (!_loadingRecent && _errorRecent == null && _recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'No analyses yet. Your first completed case will appear here.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ),
              if (_recent.isNotEmpty) ...[
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 880;
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: wide ? 3 : 1,
                        mainAxisSpacing: 24,
                        crossAxisSpacing: 24,
                        mainAxisExtent: wide ? 400 : 420,
                      ),
                      itemCount: _recent.length,
                      itemBuilder: (context, i) {
                        final r = _recent[i];
                        final pct = _clampPct(r.confidence).round();
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: NeuroScanColors.slate200),
                            boxShadow: kElevationToShadow[1],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 176,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _thumbImage(
                                    r.image,
                                    thumbnailBytes: r.thumbnailBytes,
                                    height: 176,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.patientLabel,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: NeuroScanColors.slate800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    r.timeLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Prediction: '),
                                    TextSpan(
                                      text: r.prediction.isEmpty ? '—' : r.prediction,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: NeuroScanColors.slate800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      'Confidence',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        minHeight: 8,
                                        value: pct / 100,
                                        color: NeuroScanColors.blue600,
                                        backgroundColor: NeuroScanColors.slate100,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '$pct%',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: NeuroScanColors.slate700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],

              const NeuroScanFooter(),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
