import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/tutor/domain/chat_message.dart';
import 'package:lerndex/src/shared/widgets/message_bubble.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Inline-Formeln stehen im Satz, nicht auf eigener Zeile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MessageBubble(
          message: ChatMessage.tutor(
            r'Wir haben $\frac{3}{4}$ und $\frac{1}{8}$. **Super!**',
          ),
          childName: 'Mia',
        ),
      ),
    );

    final formulas = find.byType(Math);
    expect(formulas, findsNWidgets(2));

    // Beide Formeln hängen im selben Absatz wie der umgebende Text.
    RichText paragraphOf(Finder f) => tester.widget<RichText>(
      find.ancestor(of: f, matching: find.byType(RichText)).last,
    );
    final first = paragraphOf(formulas.at(0));
    final second = paragraphOf(formulas.at(1));
    expect(identical(first, second), isTrue);
    expect(first.text.toPlainText(), contains('Wir haben'));
    expect(first.text.toPlainText(), contains('und'));
  });

  testWidgets('Block-Formeln bleiben zentriert auf eigener Zeile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MessageBubble(
          message: ChatMessage.tutor(r'Schau: $$a^2 + b^2 = c^2$$ Klar?'),
          childName: 'Mia',
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(Math), matching: find.byType(Center)),
      findsWidgets,
    );
  });
}
