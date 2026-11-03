import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors - Classic Corporate (LinkedIn Style)
  static const Color primaryColor = Color(0xFF4364F7); // Vibrant Blue
  static const Color secondaryColor = Color(
    0xFF004182,
  ); // LinkedIn Dark Blue (Hover/Focus)
  static const Color accentColor = Color(
    0xFF057642,
  ); // LinkedIn Green (Success/Active)
  static const Color dangerColor = Color(
    0xFFCC1016,
  ); // LinkedIn Red (Alerts/Errors)

  // Surface & Background Colors
  static const Color backgroundColor = Color(
    0xFFF3F2EF,
  ); // LinkedIn Warm Off-White
  static const Color surfaceColor = Colors.white; // White card backgrounds
  static const Color darkSurface = Color(0xFF191919); // LinkedIn Dark Gray

  // Text Colors
  static const Color textPrimary = Color(0xFF191919); // LinkedIn Primary Text
  static const Color textSecondary = Color(
    0xFF666666,
  ); // LinkedIn Secondary Text

  static const Color dividerColor = Color(
    0xFFEBEBEB,
  ); // LinkedIn subtle divider

  // Gradients (LinkedIn prefers solid colors, so we use a very subtle corporate blue transition)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      Color(0xFF0052D4), // Deep Blue
      Color(0xFF4364F7), // Vibrant Blue
      Color(0xFF6FB1FC), // Light Blue/Cyan
    ],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  // Standard Radii System
  static const double radiusCard = 16.0;
  static const double radiusButton = 12.0;
  static const double radiusChip = 8.0;

  // Hardcoded UI Theme Helpers - Guarantees consistent colors across all devices regardless of OS theme
  static Color cardBg([BuildContext? context]) {
    return Colors.white;
  }

  static Color cardBorder([BuildContext? context]) {
    return const Color(0xFFE2E8F0);
  }

  static List<BoxShadow> cardShadow([BuildContext? context]) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ];
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      canvasColor: backgroundColor,
      cardColor: surfaceColor,
      dividerColor: dividerColor,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: dangerColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      fontFamilyFallback: const [
        'Inter',
        '-apple-system',
        'BlinkMacSystemFont',
        'Segoe UI',
        'Roboto',
        'Helvetica Neue',
        'Arial',
        'sans-serif',
      ],
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        labelLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: textSecondary),
        labelSmall: TextStyle(color: textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF666666), // LinkedIn Gray
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
        ),
      ),
    );
  }

  // Hardcoded Theme: Dark theme is set to lightTheme to ensure 100% consistent display across all devices
  static ThemeData get darkTheme => lightTheme;
}
