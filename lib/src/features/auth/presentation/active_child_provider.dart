import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../data/auth_repository.dart';
import '../domain/account.dart';
import '../domain/child_model.dart';

/// Verwaltet das aktuell ausgewählte Kind
/// null = Eltern-Ansicht, ChildModel = Kind ist ausgewählt (Lern-Modus)
class ActiveChildNotifier extends StateNotifier<ChildModel?> {
  ActiveChildNotifier() : super(null);

  /// Kind auswählen und in Lern-Modus wechseln
  void select(ChildModel child) {
    state = child;

    // Crashlytics-Kontext setzen → bei einem Crash sieht man welches Kind betroffen war.
    // Bewusst nur pseudonyme ID + Klasse/Level – kein Name (Kinderdaten, DSGVO).
    // Im Browser gibt es kein Crashlytics.
    if (kIsWeb) return;
    FirebaseCrashlytics.instance.setUserIdentifier(child.id);
    FirebaseCrashlytics.instance.setCustomKey('child_grade', child.grade);
    FirebaseCrashlytics.instance.setCustomKey('child_level', child.level);
  }

  /// Kind abwählen und zurück zur Eltern-Ansicht
  void deselect() {
    state = null;

    // Crashlytics-Kontext zurücksetzen → zurück in Eltern-Ansicht
    if (kIsWeb) return;
    FirebaseCrashlytics.instance.setUserIdentifier('parent_view');
  }

  /// Kind-Daten aktualisieren (z.B. nach XP-Gewinn)
  void update(ChildModel child) {
    state = child;
  }

  /// Avatar des aktiven Kindes aktualisieren (null = abwählen)
  void updateAvatar(String? avatarId) {
    if (state == null) return;
    // copyWith kann nullable Felder nicht auf null setzen (wegen ??-Operator),
    // daher manuell konstruieren — alle Felder inkl. unlockedAvatars übernehmen.
    state = ChildModel(
      id: state!.id,
      name: state!.name,
      level: state!.level,
      grade: state!.grade,
      schoolType: state!.schoolType,
      age: state!.age,
      stars: state!.stars,
      totalLearningSeconds: state!.totalLearningSeconds,
      xp: state!.xp,
      xpToNextLevel: state!.xpToNextLevel,
      streak: state!.streak,
      totalQuizzes: state!.totalQuizzes,
      perfectQuizzes: state!.perfectQuizzes,
      lastLearningDate: state!.lastLearningDate,
      lastQuizDate: state!.lastQuizDate,
      lastXPGain: state!.lastXPGain,
      selectedAvatar: avatarId,
      unlockedAvatars: state!.unlockedAvatars, // ← FIX: fehlte vorher!
    );
  }
}

/// Provider für das aktive Kind
final activeChildProvider =
    StateNotifierProvider<ActiveChildNotifier, ChildModel?>((ref) {
      return ActiveChildNotifier();
    });

/// Läuft die App auf einem gekoppelten Kindergerät? Dann ist das Kinder-
/// Dashboard die Startseite: kein Zurück zur Kinderauswahl, kein Eltern-
/// bereich.
final isChildDeviceProvider = Provider<bool>((ref) {
  return ref.watch(authStateChangesProvider).value?.isChildDevice ?? false;
});
