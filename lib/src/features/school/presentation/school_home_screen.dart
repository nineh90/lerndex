import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/school_repository.dart';
import '../domain/school_models.dart';
import 'school_class_screen.dart';
import 'school_section.dart';

/// Lehrerbereich: Klassen und Lehrkräfte einer Schule.
class SchoolHomeScreen extends ConsumerWidget {
  const SchoolHomeScreen({super.key, required this.membership});

  final SchoolMembership membership;

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
    final members = ref.watch(schoolMembersProvider(schoolId)).value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Schule' : name),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
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
                        'Noch keine Klasse. Lege die erste mit „Klasse anlegen“ an.',
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
          const SizedBox(height: 24),
          const _Header('Lehrkräfte'),
          ...members.map(
            (m) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                m.isAdmin ? Icons.admin_panel_settings : Icons.person,
                color: Colors.deepPurple,
              ),
              title: Text(m.name.isEmpty ? m.email : m.name),
              subtitle: Text(m.isAdmin ? 'Schulleitung' : 'Lehrkraft'),
              trailing: membership.isAdmin && !m.isAdmin
                  ? IconButton(
                      tooltip: 'Aus der Schule entfernen',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => _removeTeacher(context, ref, m),
                    )
                  : null,
            ),
          ),
          if (membership.isAdmin)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _invite(context, ref),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Lehrkraft einladen'),
              ),
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

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    try {
      final invite = await ref
          .read(schoolRepositoryProvider)
          .createTeacherInvite();
      if (!context.mounted) return;
      final display =
          '${invite.code.substring(0, 4)}-${invite.code.substring(4)}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lehrkraft einladen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Die Lehrkraft registriert sich in Lerndex und gibt den Code '
                'unter Einstellungen → „Einer Schule beitreten“ ein. '
                'Gültig 7 Tage, nur einmal.',
              ),
              const SizedBox(height: 16),
              SelectableText(
                display,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: display)),
              child: const Text('Kopieren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fertig'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(schoolErrorText(e))));
      }
    }
  }

  Future<void> _removeTeacher(
    BuildContext context,
    WidgetRef ref,
    SchoolMember member,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lehrkraft entfernen?'),
        content: Text(
          '${member.name.isEmpty ? member.email : member.name} hat danach '
          'keinen Zugriff mehr auf die Klassen. Das Konto selbst bleibt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(schoolRepositoryProvider).removeTeacher(member.uid);
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
