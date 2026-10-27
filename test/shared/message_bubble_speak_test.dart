import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/tutor/domain/chat_message.dart';
import 'package:lerndex/src/shared/widgets/message_bubble.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Lexi-Nachricht hat einen Vorlesen-Knopf', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        MessageBubble(
          message: ChatMessage.tutor('Hallo!'),
          childName: 'Mia',
          onSpeak: () => taps++,
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    expect(taps, 1);
  });

  testWidgets('beim Vorlesen erscheint der Stopp-Knopf', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MessageBubble(
          message: ChatMessage.tutor('Hallo!'),
          childName: 'Mia',
          onSpeak: () {},
          isSpeaking: true,
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets('ohne onSpeak kein Knopf (z.B. Nachrichten des Kindes)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(MessageBubble(message: ChatMessage.user('Hi'), childName: 'Mia')),
    );

    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });
}
