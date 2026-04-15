import 'package:flutter/material.dart';

import '../theme/neuroscan_theme.dart';
import '../widgets/neuroscan_shell.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return NeuroScanShell(
      title: 'About',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About NeuroScan AI',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: NeuroScanColors.slate900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'NeuroScan AI provides MRI-based detection for Brain Tumors and Alzheimer\'s disease using explainable AI models — aligned with the NeuroScan web platform.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: NeuroScanColors.slate600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Features',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: NeuroScanColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _bullet('AI-driven analyses with confidence scores'),
                  _bullet('Secure uploads & clinician-ready reporting'),
                  _bullet('Exportable PDF summaries for workflows'),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/home'),
                      child: const Text('Home'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bullet(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: NeuroScanColors.blue600)),
          Expanded(
            child: Text(
              t,
              style: const TextStyle(
                fontSize: 14,
                color: NeuroScanColors.slate600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
