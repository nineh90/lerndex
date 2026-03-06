// ============================================================================
// DASHBOARD MODE
// Bestimmt welches Dashboard-Layout für ein Kind angezeigt wird.
//
// Klasse 1–2  → earlyLearner   (bildbasiert, kein Lesen nötig)
// Klasse 3–4  → primaryLearner (bestehendes kindgerechtes Design)
// Klasse 5–8  → secondaryLearner (modernes Design + Personalisierung)
// ============================================================================

enum DashboardMode {
  /// Klasse 1–2: Bildbasiertes Dashboard, kein Lesetext nötig
  earlyLearner,

  /// Klasse 3–4: Kinderfreundliches Dashboard (bisheriges Design)
  primaryLearner,

  /// Klasse 5–13: Modernes Dashboard mit Theming-Optionen
  secondaryLearner,
}

/// Ermittelt den Dashboard-Mode anhand der Klassenstufe.
DashboardMode getDashboardMode(int grade) {
  if (grade <= 2) return DashboardMode.earlyLearner;
  if (grade <= 4) return DashboardMode.primaryLearner;
  return DashboardMode.secondaryLearner;
}

/// Erweiterungsmethoden für bequemen Zugriff
extension DashboardModeX on DashboardMode {
  bool get isEarlyLearner => this == DashboardMode.earlyLearner;
  bool get isPrimaryLearner => this == DashboardMode.primaryLearner;
  bool get isSecondaryLearner => this == DashboardMode.secondaryLearner;

  /// Lesbarer Name für Debugging / Logs
  String get displayName {
    switch (this) {
      case DashboardMode.earlyLearner:
        return 'Entdecker (Klasse 1–2)';
      case DashboardMode.primaryLearner:
        return 'Lern-Abenteuer (Klasse 3–4)';
      case DashboardMode.secondaryLearner:
        return 'Mein Bereich (Klasse 5–8)';
    }
  }
}
