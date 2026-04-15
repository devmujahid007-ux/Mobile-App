import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/neuroscan_api.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_shell.dart';

/// Shows a stored report when [reportId] is set (`GET /api/analyses/{report_id}`).
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, this.reportId});

  final int? reportId;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _analysis;

  @override
  void initState() {
    super.initState();
    if (widget.reportId != null) {
      _load();
    }
  }

  @override
  void didUpdateWidget(ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId && widget.reportId != null) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.reportId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await NeuroscanApi.getAnalysis(id);
      if (!mounted) return;
      setState(() {
        _analysis = data;
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

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    final confidence = a != null
        ? (a['confidence'] is num
            ? (a['confidence'] as num).toDouble()
            : double.tryParse('${a['confidence']}') ?? 0)
        : 72.4;
    final prediction = a != null ? '${a['prediction'] ?? a['label'] ?? ''}' : '—';
    final explanation = a != null ? '${a['explanation'] ?? ''}' : '';
    DateTime? dt;
    try {
      dt = DateTime.tryParse('${a?['date'] ?? ''}');
    } catch (_) {}
    final dateStr = dt != null ? DateFormat.yMMMd().format(dt.toLocal()) : '—';
    final reportLabel = widget.reportId != null ? 'Report #${widget.reportId}' : 'Demo';

    return NeuroScanShell(
      title: 'Analysis Result',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 3),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: NeuroScanColors.red600),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prediction.isEmpty ? 'Analysis' : prediction,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: NeuroScanColors.slate900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$reportLabel • $dateStr',
                          style: const TextStyle(
                            fontSize: 12,
                            color: NeuroScanColors.slate500,
                          ),
                        ),
                        if (explanation.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            explanation,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: NeuroScanColors.slate600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 76,
                            height: 76,
                            child: CircularProgressIndicator(
                              value: (confidence.clamp(0, 100)) / 100,
                              strokeWidth: 8,
                              color: NeuroScanColors.blue600,
                              backgroundColor: NeuroScanColors.slate100,
                            ),
                          ),
                          Text(
                            '${confidence.clamp(0, 100).round()}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: NeuroScanColors.slate800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Confidence',
                        style: TextStyle(
                          fontSize: 12,
                          color: NeuroScanColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (a != null && a['imageUrl'] != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          NeuroscanApi.absoluteUrl(a['imageUrl']?.toString()),
                          width: 260,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderBox(),
                        ),
                      )
                    else
                      _placeholderBox(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('Close'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: (a == null ||
                                  '${a['reportDownloadUrl'] ?? ''}'.isEmpty)
                              ? null
                              : () {
                                  final u = NeuroscanApi.absoluteUrl(
                                    a['reportDownloadUrl']?.toString(),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: SelectableText(
                                        u,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  );
                                },
                          child: const Text('Report link'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderBox() {
    return Container(
      width: 260,
      height: 220,
      decoration: BoxDecoration(
        color: NeuroScanColors.slate100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.image_outlined,
        size: 72,
        color: NeuroScanColors.slate400,
      ),
    );
  }
}
