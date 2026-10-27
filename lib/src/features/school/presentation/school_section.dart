import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/school_repository.dart';
import 'school_home_screen.dart';

/// Abschnitt „Schule“ in den Einstellungen (hinter dem Eltern-PIN):
/// Lehrerbereich öffnen – oder Schule anlegen bzw. mit Code beitreten.
class SchoolSection extends ConsumerWidget {
  const SchoolSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(schoolMembershipProvider).value;

    if (membership != null) {
      final name = ref.watch(schoolNameProvider(membership.schoolId)).value;
      return ListTile(
        leading: const Icon(Icons.school, color: Colors.deepPurple),
        title: const Text('Lehrerbereich öffnen'),
        subtitle: Text(
          name ?? '…',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SchoolHomeScreen(membership: membership),
          ),
        ),
      );
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.group_add, color: Colors.deepPurple),
          title: const Text('Einer Schule beitreten'),
          subtitle: const Text(
            'Mit dem Einladungscode deiner Schule',
            style: TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _joinSchool(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.add_business, color: Colors.deepPurple),
          title: const Text('Schule anlegen'),
          subtitle: const Text(
            'Klassen und Schüler für Lernzeiten verwalten',
            style: TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _createSchool(context, ref),
        ),
      ],
    );
  }

  Future<void> _createSchool(BuildContext context, WidgetRef ref) async {
    final name = await _askText(
      context,
      title: 'Schule anlegen',
      label: 'Name der Schule',
      hint: 'z.B. Grundschule am Wald',
      info:
          'Du wirst Schulleitung in Lerndex: Du lädst Lehrkräfte ein, alle '
          'Lehrkräfte sehen alle Klassen. Deine eigenen Kinder bleiben davon '
          'getrennt.',
    );
    if (name == null || !context.mounted) return;
    await _run(context, ref, () async {
      await ref.read(schoolRepositoryProvider).createSchool(name);
      return 'Schule angelegt';
    });
  }

  Future<void> _joinSchool(BuildContext context, WidgetRef ref) async {
    final code = await _askText(
      context,
      title: 'Einer Schule beitreten',
      label: 'Einladungscode',
      hint: 'K7MX-Q2PA',
      info: 'Den Code bekommst du von der Schulleitung in Lerndex.',
    );
    if (code == null || !context.mounted) return;
    await _run(context, ref, () async {
      final school = await ref.read(schoolRepositoryProvider).joinSchool(code);
      return 'Willkommen bei $school';
    });
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<String> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await action();
      ref.invalidate(schoolMembershipProvider);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(schoolErrorText(e)), backgroundColor: Colors.red),
      );
    }
  }
}

/// Fehlermeldung der Cloud Functions ohne technisches Drumherum.
String schoolErrorText(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  return e.toString();
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  required String hint,
  required String info,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Weiter'),
        ),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}
