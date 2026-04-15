import 'package:flutter/material.dart';

/// Tailwind-aligned palette used by the NeuroScan web app (slate + blue).
abstract final class NeuroScanColors {
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);

  static const Color blue50 = Color(0xFFEFF6FF);
  static const Color blue100 = Color(0xFFDBEAFE);
  static const Color blue400 = Color(0xFF60A5FA);
  static const Color blue600 = Color(0xFF2563EB);
  static const Color blue700 = Color(0xFF1D4ED8);
  static const Color blue900 = Color(0xFF1E3A8A);

  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray700 = Color(0xFF374151);

  static const Color red50 = Color(0xFFFEF2F2);
  static const Color red200 = Color(0xFFFECACA);
  static const Color red600 = Color(0xFFDC2626);
  static const Color red700 = Color(0xFFB91C1C);

  static const Color indigo600 = Color(0xFF4F46E5);
}

ThemeData buildNeuroScanTheme() {
  const seed = NeuroScanColors.blue600;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
    primary: NeuroScanColors.blue600,
    onPrimary: Colors.white,
    surface: Colors.white,
  );

  final borderRadius = BorderRadius.circular(12);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: NeuroScanColors.gray50,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      backgroundColor: Colors.white,
      foregroundColor: NeuroScanColors.slate800,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: NeuroScanColors.slate800,
      ),
      iconTheme: const IconThemeData(color: NeuroScanColors.slate800),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: NeuroScanColors.slate200),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: NeuroScanColors.gray300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: NeuroScanColors.blue600, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: NeuroScanColors.red600),
      ),
      labelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: NeuroScanColors.gray700,
      ),
      hintStyle: const TextStyle(color: NeuroScanColors.slate500),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: NeuroScanColors.blue600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NeuroScanColors.blue600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NeuroScanColors.slate700,
        side: const BorderSide(color: NeuroScanColors.slate200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: NeuroScanColors.blue600,
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: NeuroScanColors.slate800, fontSize: 16),
      bodyMedium: TextStyle(color: NeuroScanColors.slate600, fontSize: 14),
      bodySmall: TextStyle(color: NeuroScanColors.slate500, fontSize: 12),
      titleLarge: TextStyle(
        color: NeuroScanColors.slate900,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: NeuroScanColors.slate800,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: NeuroScanColors.blue600,
      linearTrackColor: NeuroScanColors.slate100,
    ),
  );
}
