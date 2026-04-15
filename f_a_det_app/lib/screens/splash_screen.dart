import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/neuroscan_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  // ignore: library_private_types_in_public_api
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1800), () {
      Navigator.of(context).pushReplacementNamed('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NeuroScanColors.blue50,
              Colors.white,
              NeuroScanColors.blue100,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      NeuroScanColors.blue600,
                      NeuroScanColors.indigo600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: NeuroScanColors.blue600.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.biotech,
                    size: 48, color: Colors.white),
              ),
              const SizedBox(height: 22),
              const Text(
                'NeuroScan AI',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: NeuroScanColors.slate900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Brain Tumor & Alzheimer\'s Detection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: NeuroScanColors.slate500,
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: NeuroScanColors.blue600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
