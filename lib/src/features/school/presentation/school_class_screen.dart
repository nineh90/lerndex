import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/web/browser_url.dart';
import '../../auth/domain/child_model.dart';
import '../data/school_repository.dart';
import '../domain/school_models.dart';
import 'school_section.dart';
import 'student_cards_print.dart';

/// Eine Klasse: Schüler anlegen, Anmeldekarten (QR) drucken, Schüler löschen.
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
              tooltip: 'Anmeldekarten für alle drucken',
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
                      PopupMenuItem(
                        value: 'card',
                        child: Text('Anmelde-Code (QR)'),
                      ),
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

  /// Anmeldekarten: Für ein einzelnes Kind wird der QR-Code groß angezeigt
  /// (zum Abscannen vom Bildschirm, im Browser mit „Drucken“). Für die ganze
  /// Klasse öffnet sich im Browser eine Druckseite in einem neuen Tab, in den
  /// Apps kommen die Codes nacheinander auf den Bildschirm.
  Future<void> _printCards(
    BuildContext context,
    WidgetRef ref,
    List<ChildModel> students,
  ) async {
    final single = students.length == 1;
    Object? tab;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          single
              ? 'Anmelde-Code für ${students.first.name}'
              : 'Anmeldekarten für ${students.length} Schüler',
        ),
        content: Text(
          single
              ? 'Mit diesem QR-Code meldet sich ${students.first.name} auf '
                    'einem Tablet oder Handy an: einfach mit der Kamera '
                    'scannen. Ein älterer Code von ${students.first.name} '
                    'gilt danach nicht mehr.'
              : 'Für jedes Kind entsteht eine Karte mit QR-Code zum '
                    'Ausdrucken und Ausschneiden. Damit meldet es sich auf '
                    'einem Tablet oder Handy an. Bisherige Karten der Klasse '
                    'gelten danach nicht mehr.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              // Tab sofort im Tipp öffnen, sonst blockiert der Browser ihn
              if (!single) tab = openBlankTab();
              Navigator.pop(ctx, true);
            },
            child: Text(single ? 'Code anzeigen' : 'Karten erstellen'),
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
          builder: (_) =>
              _CardsOnScreenDialog(cards: cards, schoolName: schoolName),
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

/// QR-Codes zum Abscannen direkt vom Bildschirm, bei mehreren nacheinander.
/// Im Browser zusätzlich „Drucken“ (öffnet die Druckseite in einem neuen Tab).
class _CardsOnScreenDialog extends StatefulWidget {
  const _CardsOnScreenDialog({required this.cards, required this.schoolName});
  final List<StudentCard> cards;
  final String schoolName;

  @override
  State<_CardsOnScreenDialog> createState() => _CardsOnScreenDialogState();
}

class _CardsOnScreenDialogState extends State<_CardsOnScreenDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final card = widget.cards[_index];
    final qrSize = (MediaQuery.sizeOf(context).width - 140).clamp(160.0, 280.0);
    return AlertDialog(
      title: Column(
        children: [
          Text(card.name, textAlign: TextAlign.center),
          Text(
            'Klasse ${card.className}',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
      content: SizedBox(
        width: qrSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: card.link.toString(),
              size: qrSize,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              'Mit der Kamera des Tablets oder Handys scannen.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (kIsWeb)
          TextButton.icon(
            onPressed: () {
              final tab = openBlankTab();
              writeHtmlToTab(
                tab,
                studentCardsHtml(widget.cards, schoolName: widget.schoolName),
              );
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Drucken'),
          ),
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
