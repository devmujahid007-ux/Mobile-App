import 'package:flutter/material.dart';

import '../widgets/neuroscan_footer.dart';
import '../widgets/neuroscan_shell.dart';

/// About menu item: same content as the site footer (brand, quick links, contact, legal).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: 'About',
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const NeuroScanFooter(),
            ),
          );
        },
      ),
    );
  }
}
