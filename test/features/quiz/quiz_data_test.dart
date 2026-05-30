import 'package:flutter_test/flutter_test.dart';
// question_model re-exportiert quiz_data.
import 'package:lerndex/src/features/quiz/domain/question_model.dart';

Map<String, dynamic> qjson(int grade) => {
      'grade': grade,
      'question': 'Frage Klasse $grade',
      'options': ['a', 'b'],
      'answer': 'a',
      'difficulty': 'easy',
    };

void main() {
  group('QuizData.fromJson', () {
    test('parst Subject und Fragen', () {
      final data = QuizData.fromJson({
        'subject': 'Mathe',
        'questions': [qjson(1), qjson(2)],
      });
      expect(data.subject, 'Mathe');
      expect(data.questions.length, 2);
      expect(data.questions.first, isA<Question>());
    });
  });

  group('getQuestionsForGrade', () {
    QuizData buildWith(List<int> grades) => QuizData(
          subject: 'Mathe',
          questions: grades.map((g) => Question.fromJson(qjson(g))).toList(),
        );

    test('liefert höchstens count Fragen', () {
      final data = buildWith([2, 2, 2, 2, 2, 2, 2]);
      expect(data.getQuestionsForGrade(2, count: 5).length, 5);
    });

    test('filtert auf die gewünschte Klasse wenn genug vorhanden', () {
      final data = buildWith([2, 2, 2, 2, 2, 5, 5]);
      final result = data.getQuestionsForGrade(2, count: 5);
      expect(result.every((q) => q.grade == 2), isTrue);
    });

    test('greift auf Nachbarklassen zurück wenn zu wenig vorhanden', () {
      // Nur 2 Fragen für Klasse 3, aber Nachbarn (2 und 4) vorhanden
      final data = buildWith([3, 3, 2, 4, 4]);
      final result = data.getQuestionsForGrade(3, count: 5);
      expect(result.length, greaterThanOrEqualTo(3));
    });

    test('gibt weniger als count zurück wenn nichts Passendes da ist', () {
      final data = buildWith([1, 1]);
      final result = data.getQuestionsForGrade(10, count: 5);
      expect(result.length, lessThan(5));
    });
  });
}
