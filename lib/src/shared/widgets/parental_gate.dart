import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/parent_dashboard/data/pin_repository.dart';
import '../../features/parent_dashboard/presentation/pin_input_dialog.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';
import '../../features/auth/presentation/sign_out.dart';

/// Parental Gate für Kids-Apps (Apple Guideline 1.3 / Play Families Policy):
/// Vor Käufen, externen Links und der PIN-Ersteinrichtung muss eine
/// Erwachsenen-Schranke stehen.
///
/// - Ist ein Eltern-PIN gesetzt → PIN-Abfrage.
/// - Ist (noch) kein PIN gesetzt → Rechenaufgabe, die Kinder nicht im Kopf
///   lösen (zweistellig × zweistellig, zufällig, keine feste Antwort).
Future<bool> showParentalGate(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authStateChangesProvider).value;

  bool hasPin = false;
  if (user != null) {
    try {
      hasPin = await ref.read(pinRepositoryProvider).hasPinSet(user.ownerUid);
    } catch (_) {
      // Offline o.ä. → auf die Rechenaufgabe zurückfallen statt durchwinken
    }
  }
  if (!context.mounted) return false;

  if (hasPin) {
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PinInputDialog(),
    );
    return verified == true;
  }

  return showAdultGateDialog(context);
}

/// Reine Erwachsenen-Schranke ohne PIN: zufällige Multiplikationsaufgabe.
/// Wird auch direkt genutzt, bevor ein Kind sich selbst einen PIN
/// einrichten könnte (PIN-Ersteinrichtung).
Future<bool> showAdultGateDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AdultGateDialog(),
  );
  return result == true;
}

/// Aufgabe der Erwachsenen-Schranke: zwei Faktoren von 13 bis 49, ohne
/// Zehner und Schnapszahlen (20, 33 …), damit keine leichten Aufgaben
/// entstehen. Die frühere „12–29 × 3–9“ rechnen Kinder ab Klasse 5 im Kopf.
@visibleForTesting
({int a, int b}) adultGateTask(Random random) {
  int factor() {
    while (true) {
      final n = 13 + random.nextInt(37); // 13–49
      if (n % 10 != 0 && n % 11 != 0) return n;
    }
  }

  return (a: factor(), b: factor());
}

class _AdultGateDialog extends StatefulWidget {
  const _AdultGateDialog();

  @override
  State<_AdultGateDialog> createState() => _AdultGateDialogState();
}

class _AdultGateDialogState extends State<_AdultGateDialog> {
  final _controller = TextEditingController();
  late int _a;
  late int _b;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newTask();
  }

  void _newTask() {
    final task = adultGateTask(Random());
    _a = task.a;
    _b = task.b;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    if (int.tryParse(_controller.text.trim()) == _a * _b) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = 'Das war leider falsch.';
      _newTask();
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Frag deine Eltern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Dieser Bereich ist für Erwachsene. '
            'Bitte löse die Aufgabe, um fortzufahren:',
          ),
          const SizedBox(height: 16),
          Text(
            '$_a × $_b = ?',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'Ergebnis',
              errorText: _error,
            ),
            onSubmitted: (_) => _check(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _check, child: const Text('Weiter')),
      ],
    );
  }
}

/// Vollbild-Wrapper: zeigt kindgerecht "hol deine Eltern" und gibt den
/// eigentlichen Inhalt (z.B. die Paywall) erst nach bestandenem
/// Parental Gate frei. Für Stellen, an denen ein Screen direkt aus build()
/// zurückgegeben wird und kein Dialog vorgeschaltet werden kann.
class ParentalGateScreen extends ConsumerStatefulWidget {
  final WidgetBuilder builder;
  final String message;

  const ParentalGateScreen({
    super.key,
    required this.builder,
    this.message =
        'Hier geht es um Abos und Käufe – das ist Elternsache! '
        'Hol bitte deine Mama oder deinen Papa dazu. 😊',
  });

  @override
  ConsumerState<ParentalGateScreen> createState() => _ParentalGateScreenState();
}

class _ParentalGateScreenState extends ConsumerState<ParentalGateScreen> {
  bool _passed = false;

  @override
  Widget build(BuildContext context) {
    if (_passed) return widget.builder(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.family_restroom_rounded,
                  size: 72,
                  color: Color(0xFF6B21A8),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6B21A8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  onPressed: () async {
                    final ok = await showParentalGate(context, ref);
                    if (ok && mounted) setState(() => _passed = true);
                  },
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Ich bin ein Elternteil'),
                ),
                const SizedBox(height: 16),
                // Sonst gäbe es ohne Abo keinen Weg aus diesem Screen
                TextButton(
                  onPressed: () => confirmSignOut(context, ref),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
