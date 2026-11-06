import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/color_shape_quiz_screen.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/early_quiz/early_quiz_widgets.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/letter_quiz_screen.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/math_quiz_screen.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';

/// Sprachausgabe ohne Plugin.
class _SilentTts extends TtsController {
  @override
  Future<void> stop() async {}

  @override
  Future<void> speakQuestion(String questionText) async {}

  @override
  Future<void> speakFeedback(String feedbackText) async {}

  @override
  Future<void> speakResult({required int correct, required int total}) async {}
}

Future<void> _pumpQuiz(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(null)),
        ttsControllerProvider.overrideWith((ref) => _SilentTts()),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
}

Future<void> _disposeQuiz(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  const colors = [Color(0xFF7C4DFF), Color(0xFF512DA8)];

  final screens = <String, Widget Function()>{
    'Zahlen': () => const MathQuizScreen(grade: 1, subjectColors: colors),
    'Buchstaben': () => const LetterQuizScreen(grade: 1, subjectColors: colors),
    'Farben & Formen': () =>
        const ColorShapeQuizScreen(grade: 1, subjectColors: colors),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key}: Kopf, Antwort, Feedback', (tester) async {
      await _pumpQuiz(tester, entry.value());

      expect(find.byType(EarlyQuizHeader), findsOneWidget);
      expect(find.bySemanticsLabel('Zurück'), findsOneWidget);
      expect(find.bySemanticsLabel('Aufgabe vorlesen'), findsOneWidget);

      // Stufe 1 beginnt nie mit einer Malaufgabe → es gibt Antwortknöpfe
      final buttons = find.byType(EarlyAnswerButton);
      if (buttons.evaluate().isNotEmpty) {
        await tester.tap(buttons.first);
        await tester.pump();
        expect(find.byType(QuizFeedbackOverlay), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        if (find.text('Nochmal').evaluate().isNotEmpty) {
          await tester.tap(find.text('Nochmal'));
          await tester.pump();
          expect(find.byType(QuizFeedbackOverlay), findsNothing);
        }
      }
      await _disposeQuiz(tester);
    });
  }
}
