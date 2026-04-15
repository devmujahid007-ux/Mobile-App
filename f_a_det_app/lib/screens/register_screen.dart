import 'package:flutter/material.dart';

import '../services/neuroscan_api.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_shell.dart';

enum _Role { patient, doctor }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  _Role _role = _Role.patient;
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _age = TextEditingController();
  final _license = TextEditingController();
  final _specialty = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _error;
  final Map<String, String> _fieldErr = {};

  void _onRole(_Role r) {
    setState(() {
      _role = r;
      _fieldErr.clear();
      _error = null;
    });
  }

  bool _validate() {
    _fieldErr.clear();
    void req(String key, String v, String label) {
      if (v.trim().isEmpty) _fieldErr[key] = 'Required';
    }

    req('fullName', _fullName.text, '');
    req('email', _email.text, '');
    req('password', _pass.text, '');
    if (_role == _Role.patient) {
      req('age', _age.text, '');
    } else {
      req('license', _license.text, '');
      req('specialty', _specialty.text, '');
    }
    final em = _email.text.trim();
    if (em.isNotEmpty && !RegExp(r'\S+@\S+\.\S+').hasMatch(em)) {
      _fieldErr['email'] = 'Invalid email';
    }
    if (_pass.text.isNotEmpty && _pass.text.length < 6) {
      _fieldErr['password'] = 'Min 6 chars';
    }
    if (_role == _Role.patient) {
      final a = int.tryParse(_age.text.trim());
      if (a == null) {
        _fieldErr['age'] = 'Enter a valid age';
      } else if (a < 1 || a > 120) {
        _fieldErr['age'] = 'Age must be 1–120';
      }
    }
    return _fieldErr.isEmpty;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_validate()) {
      setState(() {});
      return;
    }
    setState(() => _loading = true);
    try {
      final role = _role == _Role.doctor ? 'doctor' : 'patient';
      final age = _role == _Role.patient ? int.tryParse(_age.text.trim()) : null;
      final phone = _role == _Role.doctor
          ? 'License: ${_license.text.trim()} · Specialty: ${_specialty.text.trim()}'
          : null;
      await NeuroscanApi.register(
        email: _email.text.trim(),
        password: _pass.text,
        role: role,
        name: _fullName.text.trim(),
        age: age,
        phone: phone,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _pass.dispose();
    _age.dispose();
    _license.dispose();
    _specialty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: 'Register',
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NeuroScanColors.blue50,
              NeuroScanColors.blue100,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Material(
                  color: Colors.white,
                  elevation: 8,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Create an account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: NeuroScanColors.blue700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose a role and fill in the required details.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: NeuroScanColors.slate600, fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ChoiceChip(
                              label: const Text('Patient'),
                              selected: _role == _Role.patient,
                              selectedColor: NeuroScanColors.blue600,
                              labelStyle: TextStyle(
                                color: _role == _Role.patient
                                    ? Colors.white
                                    : NeuroScanColors.slate800,
                                fontWeight: FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: _role == _Role.patient
                                    ? NeuroScanColors.blue600
                                    : NeuroScanColors.slate200,
                              ),
                              onSelected: (_) => _onRole(_Role.patient),
                            ),
                            const SizedBox(width: 10),
                            ChoiceChip(
                              label: const Text('Doctor'),
                              selected: _role == _Role.doctor,
                              selectedColor: NeuroScanColors.blue600,
                              labelStyle: TextStyle(
                                color: _role == _Role.doctor
                                    ? Colors.white
                                    : NeuroScanColors.slate800,
                                fontWeight: FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: _role == _Role.doctor
                                    ? NeuroScanColors.blue600
                                    : NeuroScanColors.slate200,
                              ),
                              onSelected: (_) => _onRole(_Role.doctor),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: const TextStyle(
                                  color: NeuroScanColors.red600, fontSize: 14)),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _fullName,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            errorText: _fieldErr['fullName'],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                            errorText: _fieldErr['email'],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          obscureText: !_showPass,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Create a password',
                            errorText: _fieldErr['password'],
                            suffixIcon: TextButton(
                              onPressed: () =>
                                  setState(() => _showPass = !_showPass),
                              child: Text(_showPass ? 'Hide' : 'Show'),
                            ),
                          ),
                        ),
                        if (_role == _Role.patient) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _age,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Age',
                              errorText: _fieldErr['age'],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _license,
                            decoration: InputDecoration(
                              labelText: 'Medical License #',
                              errorText: _fieldErr['license'],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _specialty,
                            decoration: InputDecoration(
                              labelText: 'Specialty',
                              errorText: _fieldErr['specialty'],
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Sign up'),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account? ',
                              style: TextStyle(
                                  color: NeuroScanColors.slate600, fontSize: 14),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pushReplacementNamed(
                                      context, '/login'),
                              child: const Text('Login'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ),
    );
  }
}
