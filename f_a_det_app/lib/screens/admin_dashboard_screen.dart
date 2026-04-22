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

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _notice;
  String _query = '';

  String _role = 'patient';
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _doctors = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await AuthGuard.redirectIfUnauthenticated(context);
      if (ok) await _load();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredPatients {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _patients;
    return _patients.where((p) {
      final name = '${p['name'] ?? ''}'.toLowerCase();
      final email = '${p['email'] ?? ''}'.toLowerCase();
      final phone = '${p['phone'] ?? ''}'.toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredDoctors {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _doctors;
    return _doctors.where((d) {
      final name = '${d['name'] ?? ''}'.toLowerCase();
      final email = '${d['email'] ?? ''}'.toLowerCase();
      final phone = '${d['phone'] ?? ''}'.toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();
  }

  int get _totalUsers => _patients.length + _doctors.length;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        NeuroscanApi.listPatients(),
        NeuroscanApi.listDoctors(),
      ]);
      if (!mounted) return;
      final patients = results[0].whereType<Map<String, dynamic>>().toList();
      final doctors = results[1].whereType<Map<String, dynamic>>().toList();
      setState(() {
        _patients = patients;
        _doctors = doctors;
        _loading = false;
      });
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _patients = [];
        _doctors = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addUser() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final ageText = _ageCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Name and email are required.');
      return;
    }
    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    int? age;
    if (_role == 'patient' && ageText.isNotEmpty) {
      age = int.tryParse(ageText);
      if (age == null || age < 0) {
        setState(() => _error = 'Age must be a valid non-negative number.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_role == 'doctor') {
        final result = await NeuroscanApi.createDoctor(
          name: name,
          email: email,
          phone: phone.isEmpty ? null : phone,
          password: password,
        );
        final temp = result['temporary_password'];
        final suffix = temp != null && '$temp'.isNotEmpty ? ' Temporary password: $temp' : '';
        _notice = 'Doctor added successfully.$suffix';
      } else {
        await NeuroscanApi.createPatient(
          name: name,
          email: email,
          phone: phone.isEmpty ? null : phone,
          age: age,
          password: password,
        );
        _notice = 'Patient added successfully. They can sign in with this email and password.';
      }
      if (!mounted) return;
      setState(() {
        _nameCtrl.clear();
        _emailCtrl.clear();
        _phoneCtrl.clear();
        _ageCtrl.clear();
        _passwordCtrl.clear();
        _role = 'patient';
        _submitting = false;
      });
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _submitting = false;
      });
    }
  }

  Future<void> _deleteUser({
    required String role,
    required int id,
    required String label,
  }) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm delete'),
            content: Text('Delete $role "$label"? This updates the database.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      if (role == 'doctor') {
        await NeuroscanApi.deleteDoctor(id);
      } else {
        await NeuroscanApi.deletePatient(id);
      }
      if (!mounted) return;
      setState(() {
        _notice = '${role == 'doctor' ? 'Doctor' : 'Patient'} deleted successfully.';
      });
      await _load();
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Widget _statCard(String title, String value, IconData icon) {
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
              ],
            ),
          ),
        ],
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
                  const Text(
                    'Manage doctors and patients: add users, delete users, and view complete user lists.',
                    style: TextStyle(fontSize: 13, color: NeuroScanColors.slate600),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Text(_notice!, style: TextStyle(fontSize: 13, color: Colors.green.shade800)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard('Patients', '${_patients.length}', Icons.person_outline),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard('Doctors', '${_doctors.length}', Icons.medical_information_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _statCard('Total Users', '$_totalUsers', Icons.groups_outlined),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NeuroScanColors.slate200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Add User',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: NeuroScanColors.slate800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _role,
                          items: const [
                            DropdownMenuItem(value: 'patient', child: Text('Patient')),
                            DropdownMenuItem(value: 'doctor', child: Text('Doctor')),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Role',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: _submitting
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  setState(() => _role = v);
                                },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Phone (optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        if (_role == 'patient') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _ageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Age (optional)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password (min 6 chars)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'User signs in with this email and password.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _submitting ? null : _addUser,
                          child: _submitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Add User'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'All users',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: NeuroScanColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search name, email, phone...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 10),
                  _roleSection(
                    title: 'Patients',
                    role: 'patient',
                    users: _filteredPatients,
                  ),
                  const SizedBox(height: 12),
                  _roleSection(
                    title: 'Doctors',
                    role: 'doctor',
                    users: _filteredDoctors,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _roleSection({
    required String title,
    required String role,
    required List<Map<String, dynamic>> users,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NeuroScanColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${users.length})',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: NeuroScanColors.slate800,
            ),
          ),
          const SizedBox(height: 10),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No users found.',
                style: TextStyle(color: NeuroScanColors.slate500),
              ),
            )
          else
            ...users.map((u) {
              final id = _parseId(u['id']);
              final label = '${u['name'] ?? '${role[0].toUpperCase()}${role.substring(1)} #${id ?? '?'}'}';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: NeuroScanColors.slate200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  title: Text(label),
                  subtitle: Text('${u['email'] ?? '—'}'),
                  trailing: FilledButton.tonal(
                    onPressed: id == null
                        ? null
                        : () => _deleteUser(
                              role: role,
                              id: id,
                              label: label,
                            ),
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
