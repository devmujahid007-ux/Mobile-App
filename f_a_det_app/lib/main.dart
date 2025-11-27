// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Import screens (ensure these files exist in lib/screens/)
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/upload_mri_screen.dart';
import 'screens/results_screen.dart';
import 'screens/patient_dashboard_screen.dart';
import 'screens/doctor_dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/about_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const NeuroScanApp());
}

class NeuroScanApp extends StatelessWidget {
  const NeuroScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Colors.indigo;
    final colorScheme = ColorScheme.fromSeed(seedColor: seed);

    return MaterialApp(
      title: 'NeuroScan AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),

      // Start at splash so you keep existing flow; splash will route to /home
      home: const SplashScreen(),

      // Centralized named routes used throughout the app
      routes: {
        '/home': (_) => const HomeScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/upload': (_) => const UploadMRIScreen(),
        '/results': (_) => const ResultsScreen(),
        '/patient-dashboard': (_) => const PatientDashboardScreen(),
        '/doctor-dashboard': (_) => const DoctorDashboardScreen(),
        '/admin-dashboard': (_) => const AdminDashboardScreen(),
        '/about': (_) => const AboutScreen(),
      },

      // Helpful unknown route page
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Page not found')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline,
                    size: 64, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text('No route for ${settings.name}',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pushReplacementNamed('/home'),
                  child: const Text('Go Home'),
                )
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
