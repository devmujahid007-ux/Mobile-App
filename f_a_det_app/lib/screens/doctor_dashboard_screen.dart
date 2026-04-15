import 'package:flutter/material.dart';

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

/// Doctor workflow aligned with web `DoctorDashboardPage.jsx` (requests queue).
class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  String? _notice;
  List<Map<String, dynamic>> _requests = [];
  final Set<int> _runBusy = {};
  final Set<int> _sendBusy = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await AuthGuard.redirectIfUnauthenticated(context);
      if (ok) await _load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final req = await NeuroscanApi.getDoctorRequests();
      if (!mounted) return;
      setState(() {
        _requests = req.whereType<Map<String, dynamic>>().toList();
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

  List<Map<String, dynamic>> _byStatus(String status) {
    return _requests
        .where((r) => '${r['status']}'.toLowerCase() == status.toLowerCase())
        .toList();
  }

  int? _reportId(Map<String, dynamic> scan) {
    final d = scan['diagnosis'];
    if (d is! Map) return null;
    final rep = d['report'];
    if (rep is! Map) return null;
    return _parseId(rep['id']);
  }

  String _patientLabel(Map<String, dynamic> scan) {
    final p = scan['patient'];
    if (p is Map) {
      return '${p['name'] ?? p['email'] ?? 'Patient'}';
    }
    return 'Patient';
  }

  Future<void> _run(int scanId) async {
    setState(() {
      _runBusy.add(scanId);
      _error = null;
      _notice = null;
    });
    try {
      await NeuroscanApi.runAnalysis(scanId);
      if (!mounted) return;
      setState(() => _notice = 'Analysis completed for scan #$scanId.');
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _runBusy.remove(scanId));
    }
  }

  Future<void> _send(int scanId) async {
    setState(() {
      _sendBusy.add(scanId);
      _error = null;
      _notice = null;
    });
    try {
      await NeuroscanApi.sendReport(scanId);
      if (!mounted) return;
      setState(() => _notice = 'Report sent to patient for scan #$scanId.');
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sendBusy.remove(scanId));
    }
  }

  Widget _requestCard(
    Map<String, dynamic> r, {
    required bool showRun,
    required bool showSend,
  }) {
    final id = _parseId(r['id']) ?? 0;
    final diag = r['diagnosis'];
    final pred = diag is Map ? '${diag['prediction'] ?? ''}' : '';
    final conf = diag is Map ? diag['confidence'] : null;
    final rid = _reportId(r);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _patientLabel(r),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: NeuroScanColors.slate800,
              ),
            ),
            Text(
              'Scan #$id · ${r['status']}'
              '${pred.isNotEmpty ? ' · $pred' : ''}'
              '${conf != null ? ' ($conf%)' : ''}',
              style: const TextStyle(
                fontSize: 13,
                color: NeuroScanColors.slate600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (showRun)
                  FilledButton(
                    onPressed: _runBusy.contains(id) ? null : () => _run(id),
                    child: _runBusy.contains(id)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Run analysis'),
                  ),
                if (showSend)
                  FilledButton.tonal(
                    onPressed: _sendBusy.contains(id) ? null : () => _send(id),
                    child: _sendBusy.contains(id)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send report to patient'),
                  ),
                if (rid != null)
                  OutlinedButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      '/results',
                      arguments: {'id': rid},
                    ),
                    child: const Text('Open report'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBody(String a, String b, String c, bool runA, bool sendB) {
    final la = _byStatus(a);
    final lb = _byStatus(b);
    final lc = _byStatus(c);
    return TabBarView(
      controller: _tabs,
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (la.isEmpty)
                const Text(
                  'No open requests.',
                  style: TextStyle(color: NeuroScanColors.slate500),
                )
              else
                ...la.map((r) => _requestCard(r, showRun: runA, showSend: false)),
            ],
          ),
        ),
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (lb.isEmpty)
                const Text(
                  'Nothing in analysis queue.',
                  style: TextStyle(color: NeuroScanColors.slate500),
                )
              else
                ...lb.map((r) => _requestCard(r, showRun: false, showSend: sendB)),
            ],
          ),
        ),
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (lc.isEmpty)
                const Text(
                  'No completed reports in this list.',
                  style: TextStyle(color: NeuroScanColors.slate500),
                )
              else
                ...lc.map((r) => _requestCard(r, showRun: false, showSend: false)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: 'Doctor Dashboard',
      authSlot: NeuroScanAuthSlot.account,
      additionalActions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Open'),
          Tab(text: 'Analyzed'),
          Tab(text: 'Reported'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: NeuroScanColors.red600),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _notice!,
                      style: TextStyle(color: Colors.green.shade800),
                    ),
                  ),
                Expanded(
                  child: _tabBody('sent', 'analyzed', 'reported', true, true),
                ),
              ],
            ),
    );
  }
}
