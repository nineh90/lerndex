// Farben und Theme von Lerndex an einer Stelle.
//
// Vorher gab es zwei Lilatöne nebeneinander: die Markenfarbe #6B21A8 (Logo,
// Webseite, Druckseiten) und Colors.deepPurple (#673AB7), dazu einen dritten
// aus dem Seed errechneten. Jetzt gilt überall AppColors.purple.

import 'package:flutter/material.dart';

abstract final class AppColors {
  /// Markenfarbe #6B21A8 als Palette. shade500 ist die Markenfarbe selbst;
  /// hellere und dunklere Stufen stehen im selben Verhältnis wie bei
  /// Colors.deepPurple, damit bestehende `.shade50` … `.shade800` passen.
  static const MaterialColor purple = MaterialColor(_purpleValue, {
    50: Color(0xFFFAF5FF),
    100: Color(0xFFF3E8FF),
    200: Color(0xFFE9D5FF),
    300: Color(0xFFC084FC),
    400: Color(0xFF9333EA),
    500: Color(_purpleValue),
    600: Color(0xFF621E9A),
    700: Color(0xFF581C87),
    800: Color(0xFF4C1D75),
    900: Color(0xFF3B0764),
  });
  static const int _purpleValue = 0xFF6B21A8;

  /// Für Text auf hellem Grund, der gut lesbar sein muss (≥ 4,5:1).
  static const Color textMuted = Color(0xFF616161); // grey[700]

  static const Color success = Color(0xFF15803D);
  static const Color error = Color(0xFFC62828);
  static const Color warning = Color(0xFFB45309);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      primary: AppColors.purple,
      onPrimary: Colors.white,
      error: AppColors.error,
    );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const minTarget = Size(48, 48);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: Colors.white,
          minimumSize: minTarget,
          shape: rounded,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: Colors.white,
          minimumSize: minTarget,
          shape: rounded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.purple,
          minimumSize: minTarget,
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.purple,
          minimumSize: minTarget,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.purple,
      ),
    );
  }
}
