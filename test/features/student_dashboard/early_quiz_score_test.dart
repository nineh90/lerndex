import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/early_quiz/early_quiz_session.dart';

void main() {
  group('EarlyQuizScore', () {
    test('alles beim ersten Versuch richtig → perfekt', () {
      final score = EarlyQuizScore(5);
      for (var i = 0; i < 5; i++) {
        expect(score.record(i, correct: true), EarlyQuizScore.xpFirstTry);
      }
      expect(score.correctCount, 5);
      expect(score.isPerfect, isTrue);
      expect(score.earnsTreasure, isTrue);
      expect(score.earnedXP, 15);
      expect(score.stepResults, everyElement(isTrue));
    });

    test('Raten mit „Nochmal“ ergibt kein perfektes Quiz', () {
      final score = EarlyQuizScore(5);
      for (var i = 0; i < 5; i++) {
        // erst falsch, dann Nochmal, dann richtig
        expect(score.record(i, correct: false), 0);
        score.retry(i);
        expect(score.stepResults[i], isNull);
        expect(score.record(i, correct: true), EarlyQuizScore.xpLaterTry);
      }
      expect(score.correctCount, 0);
      expect(score.isPerfect, isFalse);
      expect(score.earnsTreasure, isFalse);
      expect(score.earnedXP, 5);
      // In der Abschluss-Liste stehen alle zum Üben
      expect(score.stepResults, everyElement(isFalse));
    });

    test('ein Fehler bei sonst richtigen Antworten', () {
      final score = EarlyQuizScore(5);
      score.record(0, correct: false);
      score.retry(0);
      score.record(0, correct: true);
      for (var i = 1; i < 5; i++) {
        score.record(i, correct: true);
      }
      expect(score.correctCount, 4);
      expect(score.isPerfect, isFalse);
      expect(score.earnsTreasure, isTrue);
      expect(score.earnedXP, 4 * 3 + 1);
    });

    test('nicht erkannte Zeichnung zählt als Fehlversuch', () {
      final score = EarlyQuizScore(1);
      score.markFailedAttempt(0);
      expect(score.hasAttempted(0), isTrue);
      expect(score.record(0, correct: true), EarlyQuizScore.xpLaterTry);
      expect(score.correctCount, 0);
    });

    test('übersprungene Aufgabe: weder richtig noch falsch', () {
      final score = EarlyQuizScore(2);
      score.skip(0);
      score.record(1, correct: true);
      expect(score.stepResults, [null, true]);
      expect(score.correctCount, 1);
      expect(score.isPerfect, isFalse);
    });

    test('leeres Quiz ist nicht perfekt', () {
      expect(EarlyQuizScore(0).isPerfect, isFalse);
    });
  });
}
