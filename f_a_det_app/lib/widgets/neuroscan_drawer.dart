import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../theme/neuroscan_theme.dart';

enum NeuroScanAuthSlot { guest, account }

/// Side drawer mirroring the web Navbar sections.
class NeuroScanDrawer extends StatelessWidget {
  final NeuroScanAuthSlot authSlot;

  const NeuroScanDrawer({
    super.key,
    this.authSlot = NeuroScanAuthSlot.guest,
  });

  void _popThen(BuildContext context, String route) {
    Navigator.of(context).pop();
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/home');
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: NeuroScanColors.slate200),
                  ),
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assests/images/logo.png',
                      width: 44,
                      height: 44,
                      errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: NeuroScanColors.blue50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.psychology_outlined,
                            color: NeuroScanColors.blue600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NeuroScan',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: NeuroScanColors.slate800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Brain Tumor & Alzheimer\'s Detection',
                            style: TextStyle(
                              fontSize: 11,
                              color: NeuroScanColors.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () => _popThen(context, '/home'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () => _popThen(context, '/about'),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Contact Us'),
              onTap: () => _popThen(context, '/contact'),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NeuroScanColors.slate500,
                ),
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline, size: 22),
              title: const Text('Patient Dashboard'),
              onTap: () => _popThen(context, '/patient-dashboard'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.medical_services_outlined, size: 22),
              title: const Text('Doctor Dashboard'),
              onTap: () => _popThen(context, '/doctor-dashboard'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.admin_panel_settings_outlined, size: 22),
              title: const Text('Admin Dashboard'),
              onTap: () => _popThen(context, '/admin-dashboard'),
            ),
            const SizedBox(height: 8),
            if (authSlot == NeuroScanAuthSlot.guest) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed('/login');
                  },
                  child: const Text('Login'),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed('/register');
                  },
                  child: const Text('Sign Up'),
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: OutlinedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await AuthStorage.clearToken();
                    if (!context.mounted) return;
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login',
                      (_) => false,
                    );
                  },
                  child: const Text('Logout'),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
