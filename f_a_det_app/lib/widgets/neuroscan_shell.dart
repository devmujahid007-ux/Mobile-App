import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../theme/neuroscan_theme.dart';
import 'neuroscan_drawer.dart';
import 'neuroscan_nav_menus.dart';

/// Global layout: web-style sticky header (drawer + Dashboard + auth).
class NeuroScanShell extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? additionalActions;
  final NeuroScanAuthSlot authSlot;
  final bool showDrawer;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;

  const NeuroScanShell({
    super.key,
    required this.title,
    required this.body,
    this.additionalActions,
    this.authSlot = NeuroScanAuthSlot.guest,
    this.showDrawer = true,
    this.bottom,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < 520;
    final compactAuth = w < 420;

    final dashboard = PopupMenuButton<String>(
      tooltip: 'Dashboard',
      onSelected: (v) =>
          NeuroScanNavMenus.handleDashboardSelection(context, v),
      itemBuilder: NeuroScanNavMenus.dashboardItems,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: NeuroScanNavMenus.dashboardTrigger(narrow: narrow),
      ),
    );

    final List<Widget> navActions = [dashboard];

    if (authSlot == NeuroScanAuthSlot.guest) {
      if (compactAuth) {
        navActions.add(
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.person_outline),
            onSelected: (v) {
              if (v == 'login') {
                Navigator.of(context).pushNamed('/login');
              } else if (v == 'register') {
                Navigator.of(context).pushNamed('/register');
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'login', child: Text('Login')),
              PopupMenuItem(value: 'register', child: Text('Sign Up')),
            ],
          ),
        );
      } else {
        navActions.add(
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/login'),
            child: const Text('Login'),
          ),
        );
        navActions.add(
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pushNamed('/register'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              child: const Text('Sign Up'),
            ),
          ),
        );
      }
    } else {
      navActions.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: () async {
              await AuthStorage.clearToken();
              if (!context.mounted) return;
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (_) => false,
              );
            },
            child: const Text('Logout'),
          ),
        ),
      );
    }

    if (additionalActions != null) {
      navActions.addAll(additionalActions!);
    }

    return Scaffold(
      backgroundColor: NeuroScanColors.gray50,
      drawer: showDrawer ? NeuroScanDrawer(authSlot: authSlot) : null,
      appBar: AppBar(
        title: Text(title),
        leading: showDrawer
            ? Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              )
            : null,
        actions: navActions,
        bottom: bottom,
      ),
      body: SafeArea(child: body),
      floatingActionButton: floatingActionButton,
    );
  }
}
