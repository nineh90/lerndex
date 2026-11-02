import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/school/domain/class_stats.dart';

ChildModel _kid(
  String name, {
  int seconds = 0,
  int? quizzes,
  DateTime? learned,
  DateTime? quiz,
}) => ChildModel(
  id: name,
  name: name,
  grade: 4,
  schoolType: 'Grundschule',
  age: 9,
  totalLearningSeconds: seconds,
  totalQuizzes: quizzes,
  lastLearningDate: learned,
  lastQuizDate: quiz,
);

void main() {
  final now = DateTime(2026, 11, 3, 10);

  test('Letzte Aktivität: das späteste Datum zählt', () {
    final kid = _kid('Mia', learned: DateTime(2026, 11, 1), quiz: DateTime(2026, 11, 2, 18));
    expect(lastActivity(kid), DateTime(2026, 11, 2, 18));
    expect(lastActivity(_kid('Ben')), isNull);
  });

  test('Zuletzt aktiv als Text', () {
    expect(lastActiveLabel(null, now), 'noch nie');
    expect(lastActiveLabel(DateTime(2026, 11, 3, 8), now), 'heute');
    expect(lastActiveLabel(DateTime(2026, 11, 2, 23), now), 'gestern');
    expect(lastActiveLabel(DateTime(2026, 10, 30), now), 'vor 4 Tagen');
    expect(lastActiveLabel(DateTime(2026, 10, 25), now), 'vor einer Woche');
    expect(lastActiveLabel(DateTime(2026, 10, 1), now), 'vor 4 Wochen');
  });

  test('Lernzeit als Text', () {
    expect(durationLabel(0), '0 Min.');
    expect(durationLabel(45 * 60 + 30), '45 Min.');
    expect(durationLabel(2 * 3600), '2 Std.');
    expect(durationLabel(2 * 3600 + 5 * 60), '2 Std. 5 Min.');
  });

  test('Klassenübersicht', () {
    final summary = ClassSummary.of([
      _kid('Mia', seconds: 1200, quizzes: 3, learned: DateTime(2026, 11, 2)),
      _kid('Ben', seconds: 600, quizzes: 1, learned: DateTime(2026, 10, 1)),
      _kid('Lea'),
    ], now);
    expect(summary.students, 3);
    expect(summary.activeThisWeek, 1);
    expect(summary.totalQuizzes, 4);
    expect(summary.averageLearningSeconds, 600);
    expect(ClassSummary.of(const [], now).averageLearningSeconds, 0);
  });
}
