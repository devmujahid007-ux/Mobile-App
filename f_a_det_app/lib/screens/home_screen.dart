import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../services/neuroscan_api.dart';
import '../services/neuroscan_api_config.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/neuroscan_footer.dart';

/// ---------------- MOCK PLACEHOLDERS (safe defaults) ----------------
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

class ExampleOutcome {
  final String heading;
  final String title;
  final String confidenceText;
  final String note;

  const ExampleOutcome({
    required this.heading,
    required this.title,
    required this.confidenceText,
    required this.note,
  });

  factory ExampleOutcome.fromJson(Map<String, dynamic> j) => ExampleOutcome(
        heading: (j['heading'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        confidenceText: (j['confidenceText'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
      );
}

class RecentAnalysis {
  final String id;
  /// Set when backend exposes a numeric report id (`GET /api/analyses/{id}`).
  final int? reportId;
  final String? image; // asset or network path
  final String prediction;
  final num confidence;
  final String patientLabel;
  final String timeLabel;
  final String viewUrl;
  final String downloadUrl;

  const RecentAnalysis({
    required this.id,
    this.reportId,
    this.image,
    required this.prediction,
    required this.confidence,
    required this.patientLabel,
    required this.timeLabel,
    required this.viewUrl,
    required this.downloadUrl,
  });

  factory RecentAnalysis.fromBackend(Map<String, dynamic> j) {
    final idRaw = j['id'];
    int? rid;
    if (idRaw is int) {
      rid = idRaw;
    } else if (idRaw is String) {
      rid = int.tryParse(idRaw);
    }
    final patient = j['patient'];
    var patientLabel = 'MRI Study';
    if (patient is Map) {
      final n = patient['name'] ?? patient['email'] ?? 'Patient';
      final fn = j['fileName'] ?? j['file_name'] ?? 'scan';
      patientLabel = '$n · $fn';
    }
    DateTime? dt;
    try {
      dt = DateTime.tryParse('${j['date'] ?? ''}');
    } catch (_) {}
    final fmt = DateFormat.yMMMd().add_jm();
    return RecentAnalysis(
      id: '$idRaw',
      reportId: rid,
      image: NeuroscanApi.absoluteUrl(j['imageUrl']?.toString()),
      prediction: '${j['prediction'] ?? j['label'] ?? ''}',
      confidence: j['confidence'] is num
          ? j['confidence'] as num
          : num.tryParse('${j['confidence']}') ?? 0,
      patientLabel: patientLabel,
      timeLabel: dt != null ? fmt.format(dt.toLocal()) : '—',
      viewUrl: '/results',
      downloadUrl: NeuroscanApi.absoluteUrl(j['reportDownloadUrl']?.toString()),
    );
  }

  factory RecentAnalysis.fromJson(Map<String, dynamic> j) => RecentAnalysis(
        id: (j['id'] ?? '').toString(),
        reportId: j['reportId'] is int
            ? j['reportId'] as int
            : int.tryParse('${j['reportId'] ?? ''}'),
        image: j['image']?.toString(),
        prediction: (j['prediction'] ?? '').toString(),
        confidence: (j['confidence'] is num)
            ? j['confidence'] as num
            : num.tryParse('${j['confidence']}') ?? 0,
        patientLabel: (j['patientLabel'] ?? 'MRI Study').toString(),
        timeLabel: (j['timeLabel'] ?? 'Just now').toString(),
        viewUrl: (j['viewUrl'] ?? '/results').toString(),
        downloadUrl: (j['downloadUrl'] ?? '/results/download').toString(),
      );
}

const _mockHomeSteps = <HowItWorksStep>[
  HowItWorksStep(
      step: 1,
      title: 'Upload MRI',
      desc: 'Add DICOM/NIfTI or images for analysis.'),
  HowItWorksStep(
      step: 2,
      title: 'AI Analysis',
      desc: 'Our models scan for tumor/Alzheimer’s patterns.'),
  HowItWorksStep(
      step: 3,
      title: 'Review & Export',
      desc: 'See confidence scores and export a PDF report.'),
];

const _mockExample = ExampleOutcome(
  heading: 'Example Outcome',
  title: 'Example Model Outcome',
  confidenceText: 'Confidence: --',
  note: 'Live results shown below when available.',
);

const _mockRecent = <RecentAnalysis>[
  RecentAnalysis(
    id: 'R-1001',
    reportId: null,
    image: 'assests/images/sample1.png',
    prediction: 'Glioma',
    confidence: 92,
    patientLabel: 'Patient A • MRI Brain',
    timeLabel: '2 min ago',
    viewUrl: '/results/R-1001',
    downloadUrl: '/results/R-1001/download',
  ),
  RecentAnalysis(
    id: 'R-1002',
    reportId: null,
    image: 'assests/images/sample1.png',
    prediction: 'No abnormality',
    confidence: 97,
    patientLabel: 'Patient B • MRI Brain',
    timeLabel: '10 min ago',
    viewUrl: '/results/R-1002',
    downloadUrl: '/results/R-1002/download',
  ),
  RecentAnalysis(
    id: 'R-1003',
    reportId: null,
    image: 'assests/images/sample1.png',
    prediction: 'AMCI suspected',
    confidence: 74,
    patientLabel: 'Patient C • MRI',
    timeLabel: '25 min ago',
    viewUrl: '/results/R-1003',
    downloadUrl: '/results/R-1003/download',
  ),
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
        boxShadow: kElevationToShadow[1],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: NeuroScanColors.blue50,
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(icon, color: NeuroScanColors.blue600, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: NeuroScanColors.slate800)),
                const SizedBox(height: 6),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 13, color: NeuroScanColors.slate500)),
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
  ExampleOutcome _exampleOutcome = _mockExample;

  List<RecentAnalysis> _recent = [];
  bool _loadingRecent = true;
  String? _errorRecent;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _startPolling();
    _hydrateMeta();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
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
        _recent = List.of(_mockRecent);
        _loadingRecent = false;
        _errorRecent =
            'Could not reach ${NeuroscanApiConfig.baseUrl}. Showing samples.';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _loadRecent());
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
          if (j['exampleOutcome'] is Map<String, dynamic>) {
            final ex = ExampleOutcome.fromJson(
                j['exampleOutcome'] as Map<String, dynamic>);
            if (mounted) setState(() => _exampleOutcome = ex);
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

  Widget _thumbImage(String? path,
      {double? width, double? height, BoxFit? fit, BorderRadius? radius}) {
    Widget child;
    final p = path ?? '';
    if (p.startsWith('http')) {
      child = Image.network(
        p,
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
    } else {
      child = Image.asset(
        p.isEmpty ? 'assests/images/sample1.png' : p,
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
      title: 'NeuroScan AI',
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [NeuroScanColors.blue50, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
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
                              const Text('NeuroScan AI',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: NeuroScanColors.slate900)),
                              const Text('Brain Tumor & Alzheimer’s Detection',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: NeuroScanColors.slate500)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Early, accurate MRI-based detection for Brain Tumor & Alzheimer’s',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                            color: NeuroScanColors.slate900),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Upload MRI scans, get AI-powered analyses with confidence scores, and export professional reports for clinicians and patients. Built for research labs and clinical workflows.',
                        style: TextStyle(
                            color: NeuroScanColors.slate600, fontSize: 15),
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
                            child: const Text('Learn More'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 12,
                              color: NeuroScanColors.slate500),
                          children: const [
                            TextSpan(
                                text: 'For clinicians: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: NeuroScanColors.slate800)),
                            TextSpan(
                                text:
                                    'HIPAA-ready architecture coming soon — contact us for early access.'),
                          ],
                        ),
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
                          height: isWide ? 320 : 240,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (first != null)
                        Positioned(
                          right: 16,
                          bottom: -10,
                          child: Container(
                            width: 260,
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
                                    first.image ??
                                        'assests/images/sample1.png',
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
                                      const Text('Recent analysis',
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

              const SizedBox(height: 28),

              // ---------------- Features ----------------
              const Text('Why NeuroScan AI',
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
                      childAspectRatio: isWide ? 3.2 : 3.2,
                    ),
                    children: const [
                      FeatureCard(
                        title: 'AI-driven Diagnosis',
                        desc:
                            'State-of-the-art convolutional models trained on MRI datasets to detect lesions and patterns.',
                        icon: Icons.add,
                      ),
                      FeatureCard(
                        title: 'Secure & Compliant',
                        desc:
                            'Design-forward architecture with patient privacy and secure uploads (encryption-ready).',
                        icon: Icons.lock_outline,
                      ),
                      FeatureCard(
                        title: 'Clinician Reports',
                        desc:
                            'Downloadable PDF reports with images, predictions, and AI confidence intervals — ready for EHR upload.',
                        icon: Icons.picture_as_pdf_outlined,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // ---------------- How it works ----------------
              const Text('How it works',
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
                      childAspectRatio: isWide ? 2.2 : 2.2,
                    ),
                    itemCount: _howItWorks.length,
                    itemBuilder: (context, i) {
                      final s = _howItWorks[i];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: kElevationToShadow[1],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                            Text(s.desc,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: NeuroScanColors.slate500)),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 24),

              // ---------------- Recent Analyses ----------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Analyses',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: NeuroScanColors.slate900)),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/results'),
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (_loadingRecent)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Loading recent analyses…',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              if (!_loadingRecent && _errorRecent != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Error loading live data. Showing sample results.',
                      style:
                          TextStyle(color: Colors.red.shade600, fontSize: 13)),
                ),
              if (!_loadingRecent && _errorRecent == null && _recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'No analyses yet. Run your first analysis to see it here.',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth >= 880;
                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 3 : 1,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: isWide ? 0.92 : 1.2,
                    ),
                    itemCount: _recent.length,
                    itemBuilder: (context, i) {
                      final r = _recent[i];
                      final pct = _clampPct(r.confidence).toDouble();
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: kElevationToShadow[1],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _thumbImage(
                                r.image ?? 'assests/images/sample1.png',
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    r.patientLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(r.timeLabel,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Prediction: ${r.prediction}',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text('Confidence',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: pct / 100,
                                      color: NeuroScanColors.blue600,
                                      backgroundColor: NeuroScanColors.slate100,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${pct.toStringAsFixed(0)}%',
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: r.reportId == null
                                      ? () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'No report id yet — sign in and open from your dashboard.',
                                              ),
                                            ),
                                          );
                                        }
                                      : () {
                                          Navigator.pushNamed(
                                            context,
                                            '/results',
                                            arguments: {'id': r.reportId},
                                          );
                                        },
                                  child: const Text('View',
                                      style: TextStyle(fontSize: 12)),
                                ),
                                FilledButton(
                                  onPressed: r.downloadUrl.isEmpty
                                      ? null
                                      : () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: SelectableText(
                                                r.downloadUrl,
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                            ),
                                          );
                                        },
                                  child: const Text('Download',
                                      style: TextStyle(fontSize: 12)),
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

              const SizedBox(height: 24),

              // ---------------- Example Outcome + Supported formats ----------------
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: kElevationToShadow[1],
                ),
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final isWide = c.maxWidth >= 880;
                    final left = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Trusted by researchers',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: NeuroScanColors.slate900)),
                        const SizedBox(height: 8),
                        Text(
                          'NeuroScan AI is built on peer-reviewed research and emphasizes transparency: every prediction includes a confidence score and visual explainability maps.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                            '• Explainability maps (Grad-CAM) for clinician review',
                            style: TextStyle(
                                fontSize: 13,
                                color: NeuroScanColors.slate600)),
                        const Text('• Exportable PDF & CSV reports',
                            style: TextStyle(
                                fontSize: 13,
                                color: NeuroScanColors.slate600)),
                        const Text(
                            '• API-first design for lab integrations',
                            style: TextStyle(
                                fontSize: 13,
                                color: NeuroScanColors.slate600)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/about'),
                              child: const Text('Read papers'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/contact'),
                              child: const Text('Contact us'),
                            ),
                          ],
                        ),
                      ],
                    );
                    final right = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                NeuroScanColors.blue600,
                                NeuroScanColors.indigo600,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: kElevationToShadow[2],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_exampleOutcome.heading,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                              const SizedBox(height: 8),
                              Text(
                                '${_exampleOutcome.title} — ${_exampleOutcome.confidenceText}',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 6),
                              Text(_exampleOutcome.note,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade100)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: NeuroScanColors.slate50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Supported formats',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text('DICOM, NIfTI, PNG, JPEG',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700)),
                            ],
                          ),
                        ),
                      ],
                    );
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 16),
                          Expanded(child: right),
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        left,
                        const SizedBox(height: 16),
                        right,
                      ],
                    );
                  },
                ),
              ),
              const NeuroScanFooter(),
            ],
          ),
        ),
      ),
    );
  }
}
