import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/sign_out.dart';
import '../data/school_repository.dart';
import '../domain/school_models.dart';
import 'school_class_screen.dart';
import 'school_admin_screen.dart';

/// Startseite eines reinen Schulkontos: lädt die Schul-Rolle aus dem
/// (frischen) Token und zeigt den Schulbereich – ohne Elternbereich.
class SchoolRootScreen extends ConsumerWidget {
  const SchoolRootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<SchoolMembership?>(
      future: ref.read(schoolRepositoryProvider).membership(refresh: true),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final membership = snap.data;
        if (membership != null) {
          return schoolScreenFor(membership, isRoot: true);
        }
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Lerndex für Schulen'),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            actions: const [SchoolLogoutAction()],
          ),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Dieses Konto gehört zu keiner Schule mehr. Wenn das nicht '
                'stimmt, wenden Sie sich bitte an Ihre Schulleitung.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Schulleitung → Verwaltung der Lehrkräfte, Lehrkraft → Klassen.
Widget schoolScreenFor(SchoolMembership membership, {bool isRoot = false}) =>
    membership.isAdmin
    ? SchoolAdminScreen(membership: membership, isRoot: isRoot)
    : SchoolHomeScreen(membership: membership, isRoot: isRoot);

class SchoolLogoutAction extends ConsumerWidget {
  const SchoolLogoutAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Abmelden',
    icon: const Icon(Icons.logout_rounded),
    onPressed: () => confirmSignOut(context, ref),
  );
}

/// Lehrerbereich: alle Klassen der Schule. [isRoot]: Startseite eines
/// Lehrergeräts bzw. Schulkontos (kein Zurück, dafür Abmelden).
class SchoolHomeScreen extends ConsumerWidget {
  const SchoolHomeScreen({
    super.key,
    required this.membership,
    this.isRoot = false,
  });

  final SchoolMembership membership;
  final bool isRoot;

  static const schoolTypes = [
    'Grundschule',
    'Gymnasium',
    'Realschule',
    'Hauptschule',
    'Gesamtschule',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = membership.schoolId;
    final name = ref.watch(schoolNameProvider(schoolId)).value ?? '';
    final classes = ref.watch(schoolClassesProvider(schoolId));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isRoot,
        title: Text(name.isEmpty ? 'Schule' : name),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [if (isRoot) const SchoolLogoutAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addClass(context, ref),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Klasse anlegen'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const _Header('Klassen'),
          ...classes.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [Text('Fehler: $e')],
            data: (list) => list.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Noch keine Klasse. Legen Sie die erste mit „Klasse anlegen“ an.',
                      ),
                    ),
                  ]
                : list
                      .map(
                        (c) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.deepPurple.shade100,
                              child: Text(
                                c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ),
                            title: Text('Klasse ${c.name}'),
                            subtitle: Text('${c.grade}. Klasse · ${c.schoolType}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SchoolClassScreen(
                                  schoolId: schoolId,
                                  schoolName: name,
                                  schoolClass: c,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _addClass(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    var grade = 5;
    var schoolType = 'Gesamtschule';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Klasse anlegen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'z.B. 5b',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: grade,
                decoration: const InputDecoration(labelText: 'Klassenstufe'),
                items: [
                  for (var g = 1; g <= 10; g++)
                    DropdownMenuItem(value: g, child: Text('$g. Klasse')),
                ],
                onChanged: (v) => setState(() {
                  grade = v ?? grade;
                  if (grade <= 4) schoolType = 'Grundschule';
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: schoolType,
                decoration: const InputDecoration(labelText: 'Schulform'),
                items: [
                  for (final t in schoolTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => schoolType = v ?? schoolType),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Anlegen'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    if (ok != true || name.isEmpty) return;
    await ref
        .read(schoolRepositoryProvider)
        .addClass(
          membership.schoolId,
          name: name,
          grade: grade,
          schoolType: schoolType,
        );
  }

}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.deepPurple,
      ),
    ),
  );
}
