import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/quiz/domain/question_model.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_state.dart';

Question makeQ(String text) => Question(
      grade: 1,
      question: text,
      options: const ['a', 'b'],
      answer: 'a',
      difficulty: 'easy',
    );

void main() {
  final questions = [makeQ('Q1'), makeQ('Q2'), makeQ('Q3')];

  group('Defaults', () {
    test('frischer State ist in Phase loading', () {
      const state = QuizState();
      expect(state.phase, QuizPhase.loading);
      expect(state.currentIndex, 0);
      expect(state.questions, isEmpty);
    });
  });

  group('currentQuestion', () {
    test('liefert die Frage am aktuellen Index', () {
      final state = QuizState(questions: questions, currentIndex: 1);
      expect(state.currentQuestion?.question, 'Q2');
    });
    test('null bei leerer Fragenliste', () {
      const state = QuizState();
      expect(state.currentQuestion, isNull);
    });
    test('null wenn Index außerhalb der Grenzen', () {
      final state = QuizState(questions: questions, currentIndex: 5);
      expect(state.currentQuestion, isNull);
    });
  });

  group('isLastQuestion', () {
    test('false bei früherem Index', () {
      final state = QuizState(questions: questions, currentIndex: 0);
      expect(state.isLastQuestion, isFalse);
    });
    test('true beim letzten Index', () {
      final state = QuizState(questions: questions, currentIndex: 2);
      expect(state.isLastQuestion, isTrue);
    });
  });

  group('progress', () {
    test('0.0 bei leerer Fragenliste', () {
      const state = QuizState();
      expect(state.progress, 0.0);
    });
    test('(index + 1) / Anzahl', () {
      expect(
        QuizState(questions: questions, currentIndex: 0).progress,
        closeTo(1 / 3, 0.0001),
      );
      expect(
        QuizState(questions: questions, currentIndex: 2).progress,
        1.0,
      );
    });
  });

  group('isPerfect', () {
    test('true wenn keine falschen und keine nachgeholten Fragen', () {
      final state = QuizState(questions: questions);
      expect(state.isPerfect, isTrue);
    });
    test('false bei falscher Frage', () {
      final state = QuizState(
        questions: questions,
        wrongQuestions: [makeQ('Q1')],
      );
      expect(state.isPerfect, isFalse);
    });
    test('false wenn eine Frage erst im Retry richtig war', () {
      final state = QuizState(
        questions: questions,
        retriedCorrectly: [makeQ('Q2')],
      );
      expect(state.isPerfect, isFalse);
    });
    test('false ohne geladene Fragen', () {
      const state = QuizState();
      expect(state.isPerfect, isFalse);
    });
  });

  group('copyWith', () {
    test('ändert nur angegebene Felder', () {
      final state = QuizState(questions: questions);
      final updated = state.copyWith(
        phase: QuizPhase.feedback,
        wasCorrect: true,
        correctAnswers: 1,
      );
      expect(updated.phase, QuizPhase.feedback);
      expect(updated.wasCorrect, isTrue);
      expect(updated.correctAnswers, 1);
      expect(updated.questions, questions); // unverändert
    });

    test('errorMessage wird beim copyWith ohne Argument zurückgesetzt', () {
      const state = QuizState(errorMessage: 'Fehler');
      final cleared = state.copyWith(phase: QuizPhase.question);
      expect(cleared.errorMessage, isNull);
    });
  });
}
