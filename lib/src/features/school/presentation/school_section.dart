import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/school_repository.dart';
import 'school_home_screen.dart';

/// Abschnitt „Schule“ in den Einstellungen (hinter dem Eltern-PIN): den
/// Schulbereich öffnen, falls das Konto zu einer Schule gehört. Schulen legt
/// nur Lerndex an (Einladungslink, siehe tool/admin/schule.py), Lehrkräfte
/// melden sich mit QR-Karte + PIN an.
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
            builder: (_) => schoolScreenFor(membership),
          ),
        ),
      );
    }

    return Column(
      children: [
        const ListTile(
          leading: Icon(Icons.add_business, color: Colors.deepPurple),
          title: Text('Lerndex für Ihre Schule'),
          subtitle: Text(
            'Schulen bekommen ihren Zugang direkt von uns: support@lerndex.de',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

}

/// Fehlermeldung der Cloud Functions ohne technisches Drumherum.
String schoolErrorText(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  return e.toString();
}
