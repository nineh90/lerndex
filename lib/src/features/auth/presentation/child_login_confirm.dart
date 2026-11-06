import 'package:flutter/material.dart';

import '../data/child_device_repository.dart';

/// Rückfrage, bevor ein Link (…/k/CODE oder …/s/TOKEN) das Gerät als Kind
/// anmeldet: Ein fremder Link soll niemanden still in ein anderes Konto
/// umstellen. Der Name kommt aus der Antwort der Function.
Future<bool> confirmChildLogin(
  BuildContext context,
  ChildLogin login, {
  required bool isCard,
}) async {
  final name = login.childName.trim();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(name.isEmpty ? 'Anmelden?' : 'Als $name anmelden?'),
      content: Text(
        isCard
            ? 'Mit dieser Karte wird dieses Gerät für '
                  '${name.isEmpty ? 'ein Kind der Schule' : name} angemeldet.'
            : 'Dieses Gerät wird als eigenes Gerät von '
                  '${name.isEmpty ? 'einem Kind' : name} eingerichtet. Den '
                  'Code bekommst du von deinen Eltern.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Nein'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Ja, anmelden'),
        ),
      ],
    ),
  );
  return ok == true;
}
