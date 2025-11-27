import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroscan_ai/main.dart';

void main() {
  testWidgets('App loads home screen correctly', (WidgetTester tester) async {
    // Build the app
    await tester.pumpWidget(const NeuroScanApp());

    // Allow for initial async frames (like SplashScreen timer)
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Expect to find main home title text
    expect(find.textContaining('NeuroScan AI'), findsWidgets);

    // Expect that upload button or menu exists
    expect(find.byType(ElevatedButton), findsWidgets);

    // Open the drawer if available
    final menuButton = find.byTooltip('Open navigation menu');
    if (menuButton.evaluate().isNotEmpty) {
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      expect(find.text('Upload MRI'), findsWidgets);
    }
  });
}
