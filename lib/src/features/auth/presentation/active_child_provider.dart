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
}

/// Provider für das aktive Kind
final activeChildProvider = StateNotifierProvider<ActiveChildNotifier, ChildModel?>((ref) {
  return ActiveChildNotifier();
});