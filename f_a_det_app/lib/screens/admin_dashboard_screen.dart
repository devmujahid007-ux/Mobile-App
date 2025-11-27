import 'package:flutter/material.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Widget stat(String t, String v) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              // ignore: deprecated_member_use
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold))
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(child: stat('Total Users', '128')),
            const SizedBox(width: 12),
            Expanded(child: stat('Active Models', '2')),
          ]),
          const SizedBox(height: 12),
          const Expanded(
              child: Card(
                  child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('System Settings'),
                            SizedBox(height: 8),
                            Text('Model version: v3.2.1'),
                            Text('Server status: All systems operational'),
                          ]))))
        ]),
      ),
    );
  }
}
