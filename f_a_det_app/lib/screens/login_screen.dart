import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/auth_storage.dart';
import '../services/neuroscan_api.dart';
import '../services/neuroscan_api_config.dart';
import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _error;
  String? _emailErr;
  String? _passErr;
  String? _apiHint;
  bool _apiChecking = true;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _probeBackend());
  }

  Future<void> _probeBackend() async {
    try {
      await NeuroscanApi.fetchHealth();
      if (!mounted) return;
      setState(() {
        _apiHint = null;
        _apiChecking = false;
      });
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _apiHint = e.message;
        _apiChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiHint =
            'Cannot reach ${NeuroscanApiConfig.baseUrl}. Run the backend (uvicorn) and verify NEUROSCAN_API_URL.';
        _apiChecking = false;
      });
    }
  }

  String _humanizeUnknownLoginError(Object e) {
    final t = e.toString();
    if (t.contains('FormatException')) {
      return 'Invalid server response. Expected API at ${NeuroscanApiConfig.baseUrl}';
    }
    return 'Login failed: $e';
  }

  bool _validate() {
    _emailErr = null;
    _passErr = null;
    final email = _emailCtl.text.trim();
    final pass = _passCtl.text;
    if (email.isEmpty) {
      _emailErr = 'Email is required';
    } else if (!RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      _emailErr = 'Enter a valid email';
    }
    if (pass.isEmpty) _passErr = 'Password is required';
    return _emailErr == null && _passErr == null;
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
    });
    if (!_validate()) {
      setState(() {});
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await NeuroscanApi.login(
        _emailCtl.text.trim(),
        _passCtl.text,
      );
      final token = res['access_token'] as String?;
      if (token == null || token.isEmpty) {
        throw NeuroscanApiException('No access token from server');
      }
      final roleFromToken = AuthStorage.roleFromToken(token);
      await AuthStorage.setSession(token: token, role: roleFromToken);
      if (!mounted) return;
      final role = (roleFromToken ?? 'patient').toLowerCase();
      final next = switch (role) {
        'doctor' => '/doctor-dashboard',
        'admin' => '/admin-dashboard',
        'superadmin' => '/admin-dashboard',
        _ => '/patient-dashboard',
      };
      Navigator.of(context).pushReplacementNamed(next);
    } on NeuroscanApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanizeUnknownLoginError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: 'Login',
      showDrawer: false,
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
                constraints: const BoxConstraints(maxWidth: 440),
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
                          'Welcome Back',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: NeuroScanColors.blue700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_apiChecking)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        if (_apiHint != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Server check',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orange.shade900,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _apiHint!,
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'API: ${NeuroscanApiConfig.baseUrl} · open /health and /docs in a browser.',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: NeuroScanColors.red50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: NeuroScanColors.red200),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: NeuroScanColors.red700, fontSize: 14),
                            ),
                          ),
                        if (_error != null) const SizedBox(height: 16),
                        TextField(
                          controller: _emailCtl,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                            errorText: _emailErr,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passCtl,
                          obscureText: !_showPass,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Your password',
                            errorText: _passErr,
                            suffixIcon: TextButton(
                              onPressed: () =>
                                  setState(() => _showPass = !_showPass),
                              child: Text(_showPass ? 'Hide' : 'Show'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
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
                                : const Text('Login'),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'No account? ',
                              style: TextStyle(
                                  color: NeuroScanColors.slate600, fontSize: 14),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/register'),
                              child: const Text('Create one'),
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

