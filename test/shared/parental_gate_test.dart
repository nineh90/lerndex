import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/parent_dashboard/data/pin_repository.dart';
import 'package:lerndex/src/features/parent_dashboard/presentation/pin_input_dialog.dart';
import 'package:lerndex/src/shared/widgets/parental_gate.dart';

class _FakeUser implements User {
  @override
  String get uid => 'parent1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePinRepository implements PinRepository {
  int calls = 0;
  Completer<bool> answer = Completer<bool>();

  @override
  Future<bool> verifyPin(String userId, String pin) {
    calls++;
    return answer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Erwachsenen-Schranke', () {
    test('zweistellig × zweistellig, keine leichten Faktoren', () {
      final random = Random(1);
      for (var i = 0; i < 1000; i++) {
        final (:a, :b) = adultGateTask(random);
        for (final f in [a, b]) {
          expect(f, inInclusiveRange(13, 49));
          expect(f % 10, isNot(0));
          expect(f % 11, isNot(0));
        }
        expect(a * b, greaterThanOrEqualTo(169));
      }
    });
  });

  group('PIN-Dialog', () {
    late _FakePinRepository repo;
    late ProviderContainer container;

    Future<void> pumpDialog(WidgetTester tester) async {
      repo = _FakePinRepository();
      container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith(
            (ref) => Stream.value(_FakeUser()),
          ),
          pinRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      // Anmeldung laden (der Dialog liest sie nur per ref.read)
      container.listen(authStateChangesProvider, (_, _) {});
      await tester.pump();
      expect(container.read(authStateChangesProvider).value, isNotNull);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PinInputDialog())),
        ),
      );
    }

    testWidgets('doppeltes Enter prüft nur einmal', (tester) async {
      await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();

      expect(repo.calls, 1);

      repo.answer.complete(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Falscher PIN'), findsOneWidget);
      expect(find.textContaining('/3'), findsNothing);
    });

    testWidgets('Sperre vom Server wird angezeigt', (tester) async {
      await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Entsperren'));
      await tester.pump();

      repo.answer.completeError(
        const PinLockedException(Duration(seconds: 120)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Zu viele Fehlversuche'), findsOneWidget);
    });
  });
}
