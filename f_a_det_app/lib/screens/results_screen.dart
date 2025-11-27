import 'package:flutter/material.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const double confidence = 72.4;
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis Result')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      // ignore: deprecated_member_use
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8)
                ]),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('AMCI suspected',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('Report ID: R-2103 • Date: Oct 18, 2025',
                        style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 10),
                    const Text(
                        'Model explanation: hippocampal atrophy patterns detected. Consult a neurologist for confirmatory tests.',
                        style: TextStyle(fontSize: 13)),
                  ])),
              const SizedBox(width: 12),
              Column(children: [
                Stack(alignment: Alignment.center, children: [
                  const SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                          value: confidence / 100, strokeWidth: 8)),
                  Text('${confidence.toInt()}%',
                      style: const TextStyle(fontWeight: FontWeight.bold))
                ]),
                const SizedBox(height: 8),
                Text('Confidence',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
              ])
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 260,
                height: 220,
                color: Colors.grey.shade200,
                child: const Icon(Icons.image, size: 80)),
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close')),
              const SizedBox(width: 12),
              OutlinedButton(
                  onPressed: () {}, child: const Text('Download PDF'))
            ])
          ])))
        ]),
      ),
    );
  }
}
