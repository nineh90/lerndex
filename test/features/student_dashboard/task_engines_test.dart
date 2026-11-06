import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/color_shape_task_engine.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/letter_task_engine.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/math_task_engine.dart';

const _levels = [1, 5, 10, 15, 25];

void main() {
  group('LetterTaskEngine', () {
    final tasks = [
      for (final grade in [1, 2])
        for (final level in _levels)
          for (var seed = 0; seed < 60; seed++)
            ...LetterTaskEngine(
              grade: grade,
              level: level,
              seed: seed,
            ).generate(5),
    ];

    test('Antwort ist immer unter den Optionen, keine doppelten Optionen', () {
      for (final t in tasks.where((t) => t.options.isNotEmpty)) {
        expect(t.options, contains(t.correctAnswer), reason: t.questionText);
        expect(t.options.toSet().length, t.options.length);
      }
    });

    test(
      'Bild-Wort: echte Umlaute, Lücke passt zur Antwort, max. 7 Zeichen',
      () {
        final bildWort = tasks.where((t) => t.type == LetterTaskType.bildWort);
        expect(bildWort, isNotEmpty);
        for (final t in bildWort) {
          final word = t.fullWord!;
          expect(word, isNot(matches(RegExp('AE|OE|UE'))), reason: word);
          expect(word.length, lessThanOrEqualTo(7));
          expect(word[t.missingIndex!], t.correctAnswer);
        }
      },
    );

    test('Umlaut-Wörter kommen vor (BÄR, KÄSE, LÖWE, MÜCKE …)', () {
      final words = tasks
          .where((t) => t.type == LetterTaskType.bildWort)
          .map((t) => t.fullWord!)
          .toSet();
      expect(words.any((w) => RegExp('[ÄÖÜ]').hasMatch(w)), isTrue);
    });
  });

  group('ColorShapeTaskEngine', () {
    final tasks = [
      for (final level in _levels)
        for (var seed = 0; seed < 150; seed++)
          ...ColorShapeTaskEngine(
            grade: 1,
            level: level,
            seed: seed,
          ).generate(5),
    ];

    test('Antwort unter den Optionen, keine doppelten Optionen', () {
      for (final t in tasks.where((t) => t.options.isNotEmpty)) {
        expect(t.options, contains(t.correctAnswer), reason: t.questionText);
        expect(
          t.options.toSet().length,
          t.options.length,
          reason: '${t.type}: ${t.options}',
        );
      }
    });

    test('Formaufgaben: Antwort nie gleich dem Form-Bild der Frage', () {
      for (final t in tasks.where(
        (t) =>
            t.type == ColorShapeTaskType.gleicheForm ||
            t.type == ColorShapeTaskType.oddOneOutForm,
      )) {
        expect(t.correctAnswer, isNot(t.questionEmoji));
      }
    });

    test('Was ist KEIN …: die Lösung ist jedes Mal eine andere Form', () {
      final odd = tasks
          .where((t) => t.type == ColorShapeTaskType.oddOneOutForm)
          .toList();
      expect(odd, isNotEmpty);
      // Früher immer ein Objekt vom Kreis (bzw. Dreieck) – jetzt gemischt
      expect(odd.map((t) => t.correctAnswer).toSet().length, greaterThan(5));
    });

    test('🍕 nicht mehr bei Kreis und Dreieck gleichzeitig', () {
      for (final t in tasks.where(
        (t) => t.type == ColorShapeTaskType.gleicheForm,
      )) {
        if (t.correctAnswer == '🍕') expect(t.questionEmoji, '🔺');
      }
    });
  });

  group('MathTaskEngine', () {
    List<MathTask> gen(int grade) => [
      for (final level in _levels)
        for (var seed = 0; seed < 150; seed++)
          ...MathTaskEngine(grade: grade, level: level, seed: seed).generate(5),
    ];

    test('Zahlenstrahl: Ziel nicht immer im letzten Fünferblock', () {
      final lines = [
        ...gen(1),
        ...gen(2),
      ].where((t) => t.type == MathTaskType.numberLine).toList();
      expect(lines, isNotEmpty);
      for (final t in lines) {
        expect(t.lineTarget!, inInclusiveRange(t.lineMin!, t.lineMax!));
      }
      final notInLastBlock = lines.where(
        (t) => t.lineMax! - t.lineTarget! >= 5,
      );
      expect(notInLastBlock, isNotEmpty);
    });

    test('Malaufgabe: Ergebnis Kl. 1 ≤ 10, Kl. 2 ≤ 20', () {
      for (final grade in [1, 2]) {
        final draws = gen(
          grade,
        ).where((t) => t.type == MathTaskType.drawAnswer).toList();
        expect(draws, isNotEmpty);
        for (final t in draws) {
          final r = int.parse(t.correctAnswer);
          expect(r, inInclusiveRange(0, grade == 1 ? 10 : 20));
        }
      }
    });
  });
}
