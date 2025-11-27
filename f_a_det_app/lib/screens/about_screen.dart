import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About NeuroScan AI')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NeuroScan AI',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'NeuroScan AI provides MRI-based detection for Brain Tumors and Alzheimer\'s disease using explainable AI models.'),
          const SizedBox(height: 12),
          const Text('Features:'),
          const SizedBox(height: 6),
          const Text('• AI-driven analyses (confidence scores)'),
          const Text('• Secure uploads & reporting'),
          const Text('• Clinician-ready PDF exports'),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'))
        ]),
      ),
    );
  }
}
