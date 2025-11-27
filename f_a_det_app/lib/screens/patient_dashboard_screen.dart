import 'package:flutter/material.dart';

class PatientDashboardScreen extends StatelessWidget {
  const PatientDashboardScreen({super.key});

  Widget statCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            // ignore: deprecated_member_use
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(child: statCard('Total Reports', '12')),
            const SizedBox(width: 12),
            Expanded(child: statCard('Pending Analyses', '2')),
          ]),
          const SizedBox(height: 16),
          Expanded(
              child: ListView.builder(
                  itemCount: 3,
                  itemBuilder: (_, i) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 8),
                      leading: Container(
                          width: 56,
                          height: 48,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image)),
                      title: Text(
                          'Report R-21${i + 1} — ${i == 0 ? "Completed" : "Processing"}'),
                      subtitle: Text('Confidence: ${i == 0 ? "92%" : "75%"}'),
                      trailing: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/results'),
                          child: const Text('View')),
                    );
                  })),
        ]),
      ),
    );
  }
}
