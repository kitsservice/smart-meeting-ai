import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
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
        elevation: 8, // Very subtle shadow
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkSurface,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: primaryColor,
        surface: darkSurface,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
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
    );
  }
}
