import '../../auth/domain/child_model.dart';

// ============================================================================
// KLASSENSTATISTIK
//
// Rechnet aus den Feldern der Schüler (ChildModel) eine Übersicht für die
// Lehrkraft, ohne weitere Datenbankabfragen. Lexi-Chats bleiben außen vor.
// ============================================================================

/// Letzte Aktivität eines Kindes (Lernen, Quiz oder XP), null = noch nie.
DateTime? lastActivity(ChildModel child) {
  final dates = [
    child.lastLearningDate,
    child.lastQuizDate,
    child.lastXPGain,
  ].whereType<DateTime>();
  if (dates.isEmpty) return null;
  return dates.reduce((a, b) => a.isAfter(b) ? a : b);
}

/// „heute“, „gestern“, „vor 3 Tagen“, „noch nie“ …
String lastActiveLabel(DateTime? date, DateTime now) {
  if (date == null) return 'noch nie';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'heute';
  if (days == 1) return 'gestern';
  if (days < 7) return 'vor $days Tagen';
  if (days < 14) return 'vor einer Woche';
  if (days < 60) return 'vor ${days ~/ 7} Wochen';
  return 'vor ${days ~/ 30} Monaten';
}

/// Lernzeit kurz: „0 Min.“, „45 Min.“, „2 Std. 5 Min.“
String durationLabel(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes Min.';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours Std.' : '$hours Std. $rest Min.';
}

/// War das Kind in den letzten 7 Tagen aktiv?
bool isActiveThisWeek(ChildModel child, DateTime now) {
  final last = lastActivity(child);
  return last != null && now.difference(last).inDays < 7;
}

class ClassSummary {
  const ClassSummary({
    required this.students,
    required this.activeThisWeek,
    required this.totalLearningSeconds,
    required this.totalQuizzes,
  });

  final int students;
  final int activeThisWeek;
  final int totalLearningSeconds;
  final int totalQuizzes;

  /// Durchschnittliche Lernzeit pro Kind (gesamt)
  int get averageLearningSeconds =>
      students == 0 ? 0 : totalLearningSeconds ~/ students;

  factory ClassSummary.of(List<ChildModel> students, DateTime now) =>
      ClassSummary(
        students: students.length,
        activeThisWeek: students.where((s) => isActiveThisWeek(s, now)).length,
        totalLearningSeconds: students.fold(
          0,
          (sum, s) => sum + s.totalLearningSeconds,
        ),
        totalQuizzes: students.fold(0, (sum, s) => sum + (s.totalQuizzes ?? 0)),
      );
}
