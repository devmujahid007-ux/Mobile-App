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
import 'screens/contact_screen.dart';
import 'services/auth_guard.dart';
import 'theme/neuroscan_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const NeuroScanApp());
}

class NeuroScanApp extends StatelessWidget {
  const NeuroScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroScan',
      debugShowCheckedModeBanner: false,
      theme: buildNeuroScanTheme(),

      // Start at splash so you keep existing flow; splash will route to /home
      home: const SplashScreen(),

      // Public routes only; protected routes are resolved in onGenerateRoute.
      routes: {
        '/home': (_) => const HomeScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/upload': (_) => const UploadMRIScreen(),
        '/about': (_) => const AboutScreen(),
        '/contact': (_) => const ContactScreen(),
      },

      onGenerateRoute: (settings) {
        if (settings.name == '/patient-dashboard') {
          return MaterialPageRoute<void>(
            builder: (_) => const _ProtectedRoute(
              allowedRoles: {'patient'},
              child: PatientDashboardScreen(),
            ),
            settings: settings,
          );
        }
        if (settings.name == '/doctor-dashboard') {
          return MaterialPageRoute<void>(
            builder: (_) => const _ProtectedRoute(
              allowedRoles: {'doctor'},
              child: DoctorDashboardScreen(),
            ),
            settings: settings,
          );
        }
        if (settings.name == '/admin-dashboard') {
          return MaterialPageRoute<void>(
            builder: (_) => const _ProtectedRoute(
              allowedRoles: {'admin', 'superadmin'},
              child: AdminDashboardScreen(),
            ),
            settings: settings,
          );
        }
        if (settings.name == '/results') {
          final args = settings.arguments;
          int? reportId;
          if (args is Map && args['id'] != null) {
            final v = args['id'];
            reportId = v is int ? v : int.tryParse('$v');
          }
          return MaterialPageRoute<void>(
            builder: (_) => _ProtectedRoute(
              child: ResultsScreen(reportId: reportId),
            ),
            settings: settings,
          );
        }
        return null;
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

class _ProtectedRoute extends StatefulWidget {
  const _ProtectedRoute({
    required this.child,
    this.allowedRoles,
  });

  final Widget child;
  final Set<String>? allowedRoles;

  @override
  State<_ProtectedRoute> createState() => _ProtectedRouteState();
}

class _ProtectedRouteState extends State<_ProtectedRoute> {
  late final Future<bool> _allowedFuture;
  bool _redirectScheduled = false;

  @override
  void initState() {
    super.initState();
    _allowedFuture = AuthGuard.canAccess(allowedRoles: widget.allowedRoles);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _allowedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) return widget.child;
        if (_redirectScheduled) {
          return const Scaffold(body: SizedBox.shrink());
        }
        _redirectScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          FocusManager.instance.primaryFocus?.unfocus();
          final tokenFuture = AuthGuard.canAccess();
          tokenFuture.then((hasToken) {
            if (!context.mounted) return;
            final target = hasToken ? '/home' : '/login';
            Navigator.of(context).pushNamedAndRemoveUntil(target, (_) => false);
          });
        });
        return const Scaffold(
          body: SizedBox.shrink(),
        );
      },
    );
  }
}
