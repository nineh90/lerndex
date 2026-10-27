import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/web/browser_url.dart';
import '../../auth/domain/child_model.dart';
import '../data/school_repository.dart';
import '../domain/school_models.dart';
import 'school_section.dart';
import 'student_cards_print.dart';

/// Eine Klasse: Schüler anlegen, QR-Karten drucken, Schüler löschen.
class SchoolClassScreen extends ConsumerWidget {
  const SchoolClassScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.schoolClass,
  });

  final String schoolId;
  final String schoolName;
  final SchoolClass schoolClass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students =
        ref
            .watch(
              classStudentsProvider((
                schoolId: schoolId,
                classId: schoolClass.id,
              )),
            )
            .value ??
        const <ChildModel>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('Klasse ${schoolClass.name}'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (students.isNotEmpty)
            IconButton(
              tooltip: 'QR-Karten für alle drucken',
              icon: const Icon(Icons.print),
              onPressed: () => _printCards(context, ref, students),
            ),
          if (students.isEmpty)
            IconButton(
              tooltip: 'Leere Klasse löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(schoolRepositoryProvider)
                    .deleteClass(schoolId, schoolClass.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addStudents(context, ref),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Schüler hinzufügen'),
      ),
      body: students.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Schüler. Mit „Schüler hinzufügen“ kannst du die '
                  'ganze Klasse auf einmal eintragen.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: students.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = students[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade50,
                    child: Text(
                      s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.deepPurple),
                    ),
                  ),
                  title: Text(s.name),
                  subtitle: Text('Level ${s.level} · ${s.xp} XP'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'card':
                          _printCards(context, ref, [s]);
                        case 'rename':
                          _rename(context, ref, s);
                        case 'delete':
                          _delete(context, ref, s);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'card', child: Text('Neue Karte')),
                      PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Löschen',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _addStudents(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Schüler für ${schoolClass.name}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ein Name pro Zeile. Am besten nur Vorname und Anfangsbuchstabe '
                'des Nachnamens (Datensparsamkeit), z.B. „Mia K.“.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Mia K.\nBen S.\nLeonie W.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
    final names = parseStudentNames(text ?? '');
    if (names.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(schoolRepositoryProvider)
          .addStudents(schoolId, schoolClass, names);
      messenger.showSnackBar(
        SnackBar(content: Text('${names.length} Schüler hinzugefügt')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(schoolErrorText(e))));
    }
  }

  /// Karten erzeugen: im Browser als Druckseite in einem neuen Tab, in den
  /// Apps zum Abscannen direkt vom Bildschirm.
  Future<void> _printCards(
    BuildContext context,
    WidgetRef ref,
    List<ChildModel> students,
  ) async {
    Object? tab;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          students.length == 1
              ? 'Neue Karte für ${students.first.name}?'
              : 'Karten für ${students.length} Schüler?',
        ),
        content: const Text(
          'Mit der Karte meldet sich das Kind auf einem Tablet oder Handy an: '
          'QR-Code mit der Kamera scannen. Bisherige Karten gelten danach '
          'nicht mehr.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () {
              // Tab sofort im Tipp öffnen, sonst blockiert der Browser ihn
              tab = openBlankTab();
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.print),
            label: const Text('Karten erzeugen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final cards = await ref
          .read(schoolRepositoryProvider)
          .createCards(students, schoolClass.name);
      if (tab != null) {
        writeHtmlToTab(tab, studentCardsHtml(cards, schoolName: schoolName));
      } else if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => _CardsOnScreenDialog(cards: cards),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(schoolErrorText(e))));
      }
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    ChildModel student,
  ) async {
    final controller = TextEditingController(text: student.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Umbenennen'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(schoolRepositoryProvider)
        .renameStudent(schoolId, student.id, name);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ChildModel student,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${student.name} löschen?'),
        content: const Text(
          'Alle Daten des Kindes werden gelöscht: Fortschritt, Belohnungen, '
          'Lexi-Gespräche. Die Karte gilt nicht mehr.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(schoolRepositoryProvider).deleteStudent(student.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(schoolErrorText(e))));
    }
  }
}

/// Namen aus der Eingabe: eine Zeile pro Kind, Leerzeilen und doppelte
/// Leerzeichen fallen weg.
List<String> parseStudentNames(String text) => text
    .split(RegExp(r'[\r\n]+'))
    .map((l) => l.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((l) => l.isNotEmpty)
    .map((l) => l.length > 40 ? l.substring(0, 40) : l)
    .toList();

/// In den Apps (kein Browser-Druck): Karten nacheinander zum Abscannen.
class _CardsOnScreenDialog extends StatefulWidget {
  const _CardsOnScreenDialog({required this.cards});
  final List<StudentCard> cards;

  @override
  State<_CardsOnScreenDialog> createState() => _CardsOnScreenDialogState();
}

class _CardsOnScreenDialogState extends State<_CardsOnScreenDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final card = widget.cards[_index];
    return AlertDialog(
      title: Text(card.name),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: card.link.toString(),
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              'Zum Drucken die Klasse im Browser öffnen.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        if (_index > 0)
          TextButton(
            onPressed: () => setState(() => _index--),
            child: const Text('Zurück'),
          ),
        if (_index < widget.cards.length - 1)
          FilledButton(
            onPressed: () => setState(() => _index++),
            child: Text('Weiter (${_index + 2}/${widget.cards.length})'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fertig'),
          ),
      ],
    );
  }
}
