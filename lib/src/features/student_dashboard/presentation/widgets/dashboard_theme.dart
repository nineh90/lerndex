import 'package:flutter/material.dart';

// ============================================================================
// DASHBOARD THEME – Klasse 5+
//
// Schüler ab Klasse 5 können ihr Dashboard personalisieren:
// • 6 Farbthemes (Presets)
// • Dark Mode
// • Eigenes Hintergrundbild (Firebase Storage URL)
// ============================================================================

/// Alle verfügbaren Theme-Presets
enum DashboardThemePreset {
  midnight, // Dunkelblau – Standard ab Klasse 5
  ocean, // Türkis-Blau
  forest, // Dunkelgrün
  sunset, // Orange-Rot
  galaxy, // Lila-Dunkel
  slate, // Grau-Modern
}

/// Vollständiges Theme-Objekt mit allen Farben
class DashboardThemeData {
  final DashboardThemePreset preset;
  final String name;
  final String emoji;
  final Color primary; // Hauptfarbe (AppBar, Buttons, Akzente)
  final Color secondary; // Zweitfarbe (Gradienten, Highlights)
  final Color background; // Seiten-Hintergrund
  final Color surface; // Karten-Hintergrund
  final Color onSurface; // Text auf Karten
  final Color onPrimary; // Text auf Primary
  final bool isDark;

  const DashboardThemeData({
    required this.preset,
    required this.name,
    required this.emoji,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.onPrimary,
    required this.isDark,
  });

  /// Gradient für Header / Hero-Bereiche
  LinearGradient get headerGradient => LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Serialisierung für Firestore
  Map<String, dynamic> toMap() => {'preset': preset.name, 'isDark': isDark};

  static DashboardThemeData fromMap(Map<String, dynamic> map) {
    final presetName = map['preset'] as String? ?? 'midnight';
    final preset = DashboardThemePreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => DashboardThemePreset.midnight,
    );
    return DashboardThemes.byPreset(preset);
  }
}

/// Alle Theme-Definitionen
class DashboardThemes {
  static const midnight = DashboardThemeData(
    preset: DashboardThemePreset.midnight,
    name: 'Mitternacht',
    emoji: '🌙',
    primary: Color(0xFF5C6BC0),
    secondary: Color(0xFF3949AB),
    background: Color(0xFF0F0F1A),
    surface: Color(0xFF1C1C2E),
    onSurface: Color(0xFFE0E0E0),
    onPrimary: Colors.white,
    isDark: true,
  );

  static const ocean = DashboardThemeData(
    preset: DashboardThemePreset.ocean,
    name: 'Ozean',
    emoji: '🌊',
    primary: Color(0xFF0097A7),
    secondary: Color(0xFF006064),
    background: Color(0xFF0A1628),
    surface: Color(0xFF122038),
    onSurface: Color(0xFFE0F7FA),
    onPrimary: Colors.white,
    isDark: true,
  );

  static const forest = DashboardThemeData(
    preset: DashboardThemePreset.forest,
    name: 'Wald',
    emoji: '🌲',
    primary: Color(0xFF2E7D32),
    secondary: Color(0xFF1B5E20),
    background: Color(0xFF0A1A0A),
    surface: Color(0xFF122212),
    onSurface: Color(0xFFE8F5E9),
    onPrimary: Colors.white,
    isDark: true,
  );

  static const sunset = DashboardThemeData(
    preset: DashboardThemePreset.sunset,
    name: 'Sonnenuntergang',
    emoji: '🌅',
    primary: Color(0xFFE64A19),
    secondary: Color(0xFFBF360C),
    background: Color(0xFF1A0A00),
    surface: Color(0xFF2A1200),
    onSurface: Color(0xFFFFF3E0),
    onPrimary: Colors.white,
    isDark: true,
  );

  static const galaxy = DashboardThemeData(
    preset: DashboardThemePreset.galaxy,
    name: 'Galaxie',
    emoji: '🔮',
    primary: Color(0xFF8E24AA),
    secondary: Color(0xFF4A148C),
    background: Color(0xFF0D001A),
    surface: Color(0xFF1A0028),
    onSurface: Color(0xFFF3E5F5),
    onPrimary: Colors.white,
    isDark: true,
  );

  static const slate = DashboardThemeData(
    preset: DashboardThemePreset.slate,
    name: 'Slate',
    emoji: '🩶',
    primary: Color(0xFF455A64),
    secondary: Color(0xFF263238),
    background: Color(0xFFF5F5F5),
    surface: Colors.white,
    onSurface: Color(0xFF212121),
    onPrimary: Colors.white,
    isDark: false,
  );

  static const all = [midnight, ocean, forest, sunset, galaxy, slate];

  static DashboardThemeData byPreset(DashboardThemePreset preset) {
    return all.firstWhere((t) => t.preset == preset, orElse: () => midnight);
  }
}
