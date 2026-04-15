import 'package:flutter/material.dart';

import '../services/auth_guard.dart';
import '../services/neuroscan_api.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_drawer.dart';
import '../widgets/neuroscan_shell.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];

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
      final list = await NeuroscanApi.listUsers();
      if (!mounted) return;
      setState(() {
        _users = list.whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _users = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Widget stat(String t, String v, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NeuroScanColors.blue50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: NeuroScanColors.blue600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t,
                    style: const TextStyle(
                      fontSize: 12,
                      color: NeuroScanColors.slate500,
                    ),
                  ),
                  Text(
                    v,
                    style: const TextStyle(
                      fontSize: 20,
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
      title: 'Admin Dashboard',
      authSlot: NeuroScanAuthSlot.account,
      additionalActions: [
        IconButton(
          tooltip: 'Refresh users',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            Row(
              children: [
                stat('Total users', '${_users.length}', Icons.groups_outlined),
                const SizedBox(width: 12),
                stat('Backend', 'FastAPI', Icons.cloud_outlined),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: NeuroScanColors.red600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Users (GET /users/)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: NeuroScanColors.slate800,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: _users.isEmpty
                    ? Center(
                        child: Text(
                          _error == null && !_loading
                              ? 'No users loaded.'
                              : '',
                          style: const TextStyle(
                            color: NeuroScanColors.slate500,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: _users.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          return ListTile(
                            title: Text(
                              '${u['name'] ?? u['email']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('${u['email']} · ${u['role']}'),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
