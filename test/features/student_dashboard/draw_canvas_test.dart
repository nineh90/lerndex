import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/early_quiz/draw_canvas.dart';

final _canvas = find
    .descendant(
      of: find.byType(DrawCanvas),
      matching: find.byType(GestureDetector),
    )
    .first;

void main() {
  Future<int> pumpCanvas(
    WidgetTester tester,
    DrawingController controller, {
    VoidCallback? onSkip,
    bool enabled = true,
  }) async {
    var submits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawCanvas(
            controller: controller,
            accentColor: Colors.purple,
            enabled: enabled,
            isEvaluating: false,
            onSubmit: () => submits++,
            onSkip: onSkip,
          ),
        ),
      ),
    );
    return submits;
  }

  testWidgets('Malen füllt den Controller, Prüfen ruft onSubmit', (
    tester,
  ) async {
    final controller = DrawingController();
    var submits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawCanvas(
            controller: controller,
            accentColor: Colors.purple,
            enabled: true,
            isEvaluating: false,
            onSubmit: () => submits++,
          ),
        ),
      ),
    );

    // Leer: Prüfen tut nichts
    await tester.tap(find.text('✓ Prüfen'));
    expect(submits, 0);

    await tester.timedDrag(
      _canvas,
      const Offset(60, 40),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(controller.isNotEmpty, isTrue);
    expect(controller.strokes.single.length, greaterThan(1));

    await tester.tap(find.text('✓ Prüfen'));
    expect(submits, 1);

    // Löschen
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();
    expect(controller.isEmpty, isTrue);
    controller.dispose();
  });

  testWidgets('Weiter erscheint nur mit onSkip', (tester) async {
    final controller = DrawingController();
    await pumpCanvas(tester, controller);
    expect(find.text('Weiter ➡️'), findsNothing);

    var skipped = false;
    await pumpCanvas(tester, controller, onSkip: () => skipped = true);
    await tester.tap(find.text('Weiter ➡️'));
    expect(skipped, isTrue);
    controller.dispose();
  });

  testWidgets('gesperrt (Feedback läuft): kein Malen', (tester) async {
    final controller = DrawingController();
    await pumpCanvas(tester, controller, enabled: false);
    await tester.timedDrag(
      _canvas,
      const Offset(60, 40),
      const Duration(milliseconds: 300),
    );
    expect(controller.isEmpty, isTrue);
    controller.dispose();
  });
}
