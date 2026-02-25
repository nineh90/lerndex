import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/child_model.dart';

/// Verwaltet das aktuell ausgewählte Kind
/// null = Eltern-Ansicht, ChildModel = Kind ist ausgewählt (Lern-Modus)
class ActiveChildNotifier extends StateNotifier<ChildModel?> {
  ActiveChildNotifier() : super(null);

  /// Kind auswählen und in Lern-Modus wechseln
  void select(ChildModel child) {
    state = child;
  }

  /// Kind abwählen und zurück zur Eltern-Ansicht
  void deselect() {
    state = null;
  }

  /// Kind-Daten aktualisieren (z.B. nach XP-Gewinn)
  void update(ChildModel child) {
    state = child;
  }

  /// Avatar des aktiven Kindes aktualisieren (null = abwählen)
  void updateAvatar(String? avatarId) {
    if (state == null) return;
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
      selectedAvatar: avatarId, // explizit null erlaubt
    );
  }
}

/// Provider für das aktive Kind
final activeChildProvider =
    StateNotifierProvider<ActiveChildNotifier, ChildModel?>((ref) {
      return ActiveChildNotifier();
    });
