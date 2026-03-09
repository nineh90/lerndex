import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// TUTORIAL SYSTEM
//
// Führt neue Nutzer interaktiv durch die App:
//   Schritt 1 – FamilyDashboard:   Beide Buttons werden erklärt
//   Schritt 2 – FamilyDashboard:   Eltern-Dashboard Button highlighten → antippen
//   Schritt 3 – PIN-Dialog:        PIN eingeben (läuft automatisch weiter)
//   Schritt 4 – ParentDashboard:   „Kind hinzufügen" highlighten → antippen
//   Schritt 5 – ParentDashboard:   Kind-Dialog ausfüllen (läuft automatisch weiter)
//   Schritt 6 – FamilyDashboard:   Kind-Karte zeigen
//   Schritt 7 – ParentDashboard:   Übersicht erklären → Tutorial beenden
//
// Aktivierung: Wird nach dem Onboarding (erstes Login) gestartet.
// Deaktivierung: SharedPreferences Flag 'tutorial_completed'
// ============================================================================

enum TutorialStep {
  // Noch nicht gestartet
  inactive,

  // Schritt 1: FamilyDashboard – Überblick über die zwei Bereiche
  familyDashboardIntro,

  // Schritt 2: FamilyDashboard – Eltern-Button tippen
  tapParentButton,

  // Schritt 3: PIN-Dialog – wird automatisch erkannt wenn PIN stimmt
  enterPin,

  // Schritt 4: ParentDashboard – „Kind hinzufügen" tippen
  tapAddChild,

  // Schritt 5: Kind-Dialog – Kind anlegen (wird automatisch erkannt)
  addChild,

  // Schritt 6: FamilyDashboard – Kind-Karte zeigen
  showChildCard,

  // Schritt 7: ParentDashboard – Übersicht erklären
  parentDashboardOverview,

  // Tutorial abgeschlossen
  completed,
}

// ── State ────────────────────────────────────────────────────────────────────

class TutorialState {
  final TutorialStep step;
  final bool isVisible; // Overlay sichtbar?

  const TutorialState({required this.step, this.isVisible = true});

  TutorialState copyWith({TutorialStep? step, bool? isVisible}) {
    return TutorialState(
      step: step ?? this.step,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  bool get isActive =>
      step != TutorialStep.inactive && step != TutorialStep.completed;
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class TutorialNotifier extends StateNotifier<TutorialState> {
  TutorialNotifier()
    : super(const TutorialState(step: TutorialStep.inactive, isVisible: false));

  static const _prefKey = 'tutorial_completed';

  /// Prüft ob Tutorial bereits abgeschlossen wurde
  Future<bool> shouldShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_prefKey) ?? false);
  }

  /// Startet das Tutorial (nach erstem Onboarding).
  /// Prüft ob es bereits abgeschlossen wurde.
  Future<void> startTutorial() async {
    final shouldShow = await shouldShowTutorial();
    if (!shouldShow) return;
    state = const TutorialState(step: TutorialStep.familyDashboardIntro);
  }

  /// Startet das Tutorial sofort ohne SharedPreferences-Check.
  /// Für neue Accounts nach dem Setup-Dialog — kein async nötig.
  void forceStart() {
    state = const TutorialState(step: TutorialStep.familyDashboardIntro);
  }

  /// Tutorial zurücksetzen und neu starten – für den Replay aus den Einstellungen
  Future<void> resetAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    state = const TutorialState(step: TutorialStep.familyDashboardIntro);
  }

  /// Zum nächsten Schritt weiterschalten
  void nextStep() {
    final next = _nextStep(state.step);
    state = state.copyWith(step: next);
    if (next == TutorialStep.completed) {
      _markCompleted();
    }
  }

  /// Schritt direkt setzen (z.B. nach Navigation)
  void setStep(TutorialStep step) {
    state = state.copyWith(step: step);
  }

  /// Tutorial überspringen
  Future<void> skip() async {
    state = const TutorialState(step: TutorialStep.completed, isVisible: false);
    await _markCompleted();
  }

  /// Overlay kurz ausblenden (z.B. während Dialog offen ist)
  void hideOverlay() => state = state.copyWith(isVisible: false);
  void showOverlay() => state = state.copyWith(isVisible: true);

  Future<void> _markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  TutorialStep _nextStep(TutorialStep current) {
    switch (current) {
      case TutorialStep.familyDashboardIntro:
        return TutorialStep.tapParentButton;
      case TutorialStep.tapParentButton:
        return TutorialStep.enterPin;
      case TutorialStep.enterPin:
        return TutorialStep.tapAddChild;
      case TutorialStep.tapAddChild:
        return TutorialStep.addChild;
      case TutorialStep.addChild:
        return TutorialStep.showChildCard;
      case TutorialStep.showChildCard:
        return TutorialStep.parentDashboardOverview;
      case TutorialStep.parentDashboardOverview:
        return TutorialStep.completed;
      default:
        return TutorialStep.completed;
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final tutorialProvider = StateNotifierProvider<TutorialNotifier, TutorialState>(
  (ref) => TutorialNotifier(),
);

// ── Tooltip-Inhalte ───────────────────────────────────────────────────────────

class TutorialContent {
  final String title;
  final String body;
  final String buttonLabel;
  final IconData icon;

  const TutorialContent({
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.icon,
  });
}

const Map<TutorialStep, TutorialContent> tutorialContent = {
  TutorialStep.familyDashboardIntro: TutorialContent(
    title: 'Willkommen bei Lerndex! 👋',
    body:
        'Das ist dein Familien-Dashboard. Hier siehst du alle deine Kinder auf einen Blick. Unten findest du zwei Bereiche — schauen wir sie gemeinsam an.',
    buttonLabel: 'Weiter',
    icon: Icons.home_outlined,
  ),
  TutorialStep.tapParentButton: TutorialContent(
    title: 'Eltern-Dashboard 👨‍👩‍👧',
    body:
        'Hier verwaltest du alles: Kinder anlegen, Fortschritte einsehen, Belohnungen vergeben. Tippe jetzt auf diesen Button!',
    buttonLabel: 'Tippe auf den Button →',
    icon: Icons.family_restroom_rounded,
  ),
  TutorialStep.enterPin: TutorialContent(
    title: 'PIN-Schutz 🔒',
    body:
        'Das Eltern-Dashboard ist mit deinem PIN gesichert, damit deine Kinder nicht hineinkommen. Gib jetzt deinen PIN ein.',
    buttonLabel: 'Verstanden',
    icon: Icons.lock_outline,
  ),
  TutorialStep.tapAddChild: TutorialContent(
    title: 'Kind hinzufügen ➕',
    body:
        'Jetzt legst du dein erstes Kind an. Tippe auf „Kind hinzufügen" unten in der Leiste!',
    buttonLabel: 'Tippe auf den Button →',
    icon: Icons.person_add_outlined,
  ),
  TutorialStep.addChild: TutorialContent(
    title: 'Kind anlegen 🧒',
    body:
        'Gib Name, Alter, Klasse und Schulform ein. Lerndex passt die Fragen automatisch an das Niveau an.',
    buttonLabel: 'Verstanden',
    icon: Icons.edit_outlined,
  ),
  TutorialStep.showChildCard: TutorialContent(
    title: 'Dein Kind ist da! 🎉',
    body:
        'Super! Das Kind erscheint jetzt hier im Familien-Dashboard. Tippe auf die Karte um das Kinder-Dashboard zu öffnen. Aber erst schauen wir noch kurz ins Eltern-Dashboard.',
    buttonLabel: 'Weiter zum Eltern-Dashboard',
    icon: Icons.child_care_outlined,
  ),
  TutorialStep.parentDashboardOverview: TutorialContent(
    title: 'Alles im Blick 📊',
    body:
        'Hier siehst du live den Fortschritt deines Kindes: XP, Streak, Lernzeit und Quiz-Ergebnisse. Mit den Tabs unten erreichst du Einstellungen und kannst weitere Kinder anlegen.',
    buttonLabel: 'Tutorial abschließen ✅',
    icon: Icons.dashboard_outlined,
  ),
};
