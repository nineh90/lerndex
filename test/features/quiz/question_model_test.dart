import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/quiz/domain/question_model.dart';

Question q({
  String question = 'Was ist 2 + 2?',
  List<String> options = const ['3', '4', '5'],
  String answer = '4',
  String? emoji,
  String? parentTaskRef,
}) {
  return Question(
    grade: 1,
    question: question,
    options: options,
    answer: answer,
    difficulty: 'easy',
    emoji: emoji,
    parentTaskRef: parentTaskRef,
  );
}

void main() {
  group('isCorrect', () {
    test('exakte Übereinstimmung ist korrekt', () {
      expect(q().isCorrect('4'), isTrue);
    });
    test('abweichende Antwort ist falsch', () {
      expect(q().isCorrect('5'), isFalse);
    });
    test('ist case-sensitive', () {
      expect(q(answer: 'Apfel').isCorrect('apfel'), isFalse);
    });
  });

  group('hasEmoji / isParentTask', () {
    test('hasEmoji false ohne Emoji', () {
      expect(q().hasEmoji, isFalse);
    });
    test('hasEmoji true mit Emoji', () {
      expect(q(emoji: '🍎').hasEmoji, isTrue);
    });
    test('isParentTask abhängig von parentTaskRef', () {
      expect(q().isParentTask, isFalse);
      expect(q(parentTaskRef: 'batch/123').isParentTask, isTrue);
    });
  });

  group('fromJson', () {
    test('parst Pflichtfelder mit Defaults', () {
      final question = Question.fromJson({
        'question': 'Frage?',
        'options': ['a', 'b'],
        'answer': 'a',
      });
      expect(question.grade, 1); // Default
      expect(question.difficulty, 'medium'); // Default
      expect(question.options, ['a', 'b']);
    });

    test('akzeptiert Whitelist-Emoji', () {
      final question = Question.fromJson({
        'question': 'Wie viele?',
        'options': ['1', '2'],
        'answer': '2',
        'emoji': '🍎',
      });
      expect(question.emoji, '🍎');
    });

    test('verwirft nicht-gelistetes Emoji', () {
      final question = Question.fromJson({
        'question': 'Wie viele?',
        'options': ['1', '2'],
        'answer': '2',
        'emoji': '😀',
      });
      expect(question.emoji, isNull);
    });

    test('entfernt Bild-Platzhalter aus dem Fragetext', () {
      final question = Question.fromJson({
        'question': 'Wie viele Äpfel? (Bild eines Apfels)',
        'options': ['1', '2'],
        'answer': '2',
      });
      expect(question.question, 'Wie viele Äpfel?');
    });
  });

  group('toJson / Roundtrip', () {
    test('toJson lässt unbelegte Optionalfelder weg', () {
      final json = q().toJson();
      expect(json.containsKey('emoji'), isFalse);
      expect(json.containsKey('parentTaskRef'), isFalse);
      expect(json['answer'], '4');
    });

    test('fromJson(toJson()) erhält die Frage', () {
      final original = q(emoji: '🍎', parentTaskRef: 'b/1');
      final restored = Question.fromJson(original.toJson());
      expect(restored.question, original.question);
      expect(restored.answer, original.answer);
      expect(restored.emoji, '🍎');
      expect(restored.parentTaskRef, 'b/1');
    });
  });

  group('copyWith & Gleichheit', () {
    test('copyWith ändert nur angegebene Felder', () {
      final updated = q().copyWith(answer: '5');
      expect(updated.answer, '5');
      expect(updated.question, q().question);
    });

    test('Gleichheit basiert auf question + answer + grade', () {
      final a = q();
      final b = q(options: const ['ganz', 'andere', 'optionen']);
      expect(a, equals(b)); // gleiche question/answer/grade
      expect(a.hashCode, b.hashCode);
    });

    test('unterschiedliche Antwort → ungleich', () {
      expect(q(answer: '4'), isNot(equals(q(answer: '5'))));
    });
  });
}
