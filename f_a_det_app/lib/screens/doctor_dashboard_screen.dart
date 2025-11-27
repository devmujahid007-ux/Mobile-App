import 'package:flutter/material.dart';

class DoctorDashboardScreen extends StatelessWidget {
  const DoctorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Row(children: [
            Expanded(
                child: Card(
                    child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Column(children: [
                          Text('My Patients'),
                          SizedBox(height: 6),
                          Text('82',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold))
                        ])))),
            SizedBox(width: 12),
            Expanded(
                child: Card(
                    child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Column(children: [
                          Text('Pending'),
                          SizedBox(height: 6),
                          Text('6',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold))
                        ])))),
          ]),
          const SizedBox(height: 12),
          Expanded(
              child: ListView(
            children: [
              ListTile(
                  title: const Text('Lara Croft'),
                  subtitle: const Text('R-2041 — 92%'),
                  trailing: ElevatedButton(
                      onPressed: () {}, child: const Text('Open'))),
              ListTile(
                  title: const Text('Mark Taylor'),
                  subtitle: const Text('R-2045 — 89%'),
                  trailing: ElevatedButton(
                      onPressed: () {}, child: const Text('Open'))),
            ],
          ))
        ]),
      ),
    );
  }
}
