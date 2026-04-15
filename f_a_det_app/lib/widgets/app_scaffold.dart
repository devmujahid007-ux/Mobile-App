import 'package:flutter/material.dart';

import 'neuroscan_drawer.dart';
import 'neuroscan_shell.dart';

/// Shell with web-style navbar (drawer + Resources + Dashboard + auth).
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final NeuroScanAuthSlot authSlot;
  final bool showDrawer;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.authSlot = NeuroScanAuthSlot.guest,
    this.showDrawer = true,
  });

  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: title,
      authSlot: authSlot,
      showDrawer: showDrawer,
      additionalActions: actions,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
