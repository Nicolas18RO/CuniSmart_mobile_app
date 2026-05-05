import 'package:flutter/material.dart';

class CuniTheme {
  CuniTheme._();

  static const Color primaryGreen = Color(0xFF8FA88B);
  static const Color darkGray = Color(0xFF333333);
  static const Color lightGrayBackground = Color(0xFFF2F4F3);
  static const Color borderGray = Color(0xFFD1D6D2);
  static const Color placeholderGray = Color(0xFF8A908C);

  // Rabbits (organic green UI system)
  static const Color rabbitsBackground = Color(0xFFF3F6F3);
  static const Color rabbitsCardBackground = Color(0xFFEBF1EA);
  static const Color rabbitsPrimaryGreen = Color(0xFF86BC68);
  static const Color rabbitsTextPrimary = Color(0xFF1A2E1A);
  static const Color rabbitsTextSecondary = Color(0xFF657965);
  static const Color rabbitsDelete = Color(0xFFC85A54);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.light,
      primary: primaryGreen,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: darkGray,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkGray,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: darkGray,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightGrayBackground,
        hintStyle: const TextStyle(color: placeholderGray),
        labelStyle: const TextStyle(color: placeholderGray),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderGray,
        thickness: 1,
      ),
    );
  }
}

