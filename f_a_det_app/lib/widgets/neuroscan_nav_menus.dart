import 'package:flutter/material.dart';

import '../theme/neuroscan_theme.dart';

/// Web-aligned Resources + Dashboard menus (PopupMenuButton children).
abstract final class NeuroScanNavMenus {
  static List<PopupMenuEntry<String>> resourcesItems(BuildContext context) {
    return [
      const PopupMenuItem(
        value: 'docs',
        child: Text('Documentation'),
      ),
      const PopupMenuItem(
        value: 'papers',
        child: Text('Research Papers'),
      ),
      const PopupMenuItem(
        value: 'faq',
        child: Text('FAQ'),
      ),
    ];
  }

  static void handleResourcesSelection(BuildContext context, String? value) {
    if (value == null) return;
    if (value == 'docs' || value == 'papers' || value == 'faq') {
      Navigator.of(context).pushNamed('/about');
    }
  }

  static List<PopupMenuEntry<String>> dashboardItems(BuildContext context) {
    return const [
      PopupMenuItem(value: 'patient', child: Text('Patient Dashboard')),
      PopupMenuItem(value: 'doctor', child: Text('Doctor Dashboard')),
      PopupMenuItem(value: 'admin', child: Text('Admin Dashboard')),
    ];
  }

  static void handleDashboardSelection(BuildContext context, String? value) {
    if (value == null) return;
    if (value == 'patient') {
      Navigator.of(context).pushNamed('/patient-dashboard');
    } else if (value == 'doctor') {
      Navigator.of(context).pushNamed('/doctor-dashboard');
    } else if (value == 'admin') {
      Navigator.of(context).pushNamed('/admin-dashboard');
    }
  }

  /// Compact trigger: icon on narrow widths, text + chevron when wide enough.
  static Widget resourcesTrigger({required bool narrow}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          narrow ? Icons.folder_open : Icons.menu_book_outlined,
          size: 22,
          color: NeuroScanColors.slate700,
        ),
        if (!narrow) ...[
          const SizedBox(width: 4),
          const Text('Resources'),
          const Icon(Icons.arrow_drop_down, color: NeuroScanColors.slate700),
        ],
      ],
    );
  }

  static Widget dashboardTrigger({required bool narrow}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          narrow ? Icons.dashboard_customize_outlined : Icons.dashboard_outlined,
          size: 22,
          color: NeuroScanColors.slate700,
        ),
        if (!narrow) ...[
          const SizedBox(width: 4),
          const Text('Dashboard'),
          const Icon(Icons.arrow_drop_down, color: NeuroScanColors.slate700),
        ],
      ],
    );
  }
}
