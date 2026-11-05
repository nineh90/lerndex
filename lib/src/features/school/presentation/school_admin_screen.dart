import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/web/browser_url.dart';
import '../data/school_repository.dart';
import '../domain/school_models.dart';
import 'school_home_screen.dart' show SchoolLogoutAction;
import '../../../shared/user_message.dart';
import 'student_cards_print.dart';

/// Schulleitung: verwaltet nur die Lehrkräfte (anlegen, Karte neu ausstellen,
/// PIN zurücksetzen, entfernen) und sieht die Lizenz. Klassen und Schüler
/// legen die Lehrkräfte an – die Schulleitung sieht keine Schülerdaten.
class SchoolAdminScreen extends ConsumerWidget {
  const SchoolAdminScreen({
    super.key,
    required this.membership,
    this.isRoot = false,
  });

  final SchoolMembership membership;
  final bool isRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = membership.schoolId;
    final name = ref.watch(schoolNameProvider(schoolId)).value ?? '';
    final license = ref.watch(schoolLicenseProvider(schoolId));
    final members = ref.watch(schoolMembersProvider(schoolId));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isRoot,
        title: Text(name.isEmpty ? 'Schule' : name),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [if (isRoot) const SchoolLogoutAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTeacher(context, ref, name),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Lehrkraft anlegen'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _LicenseCard(license: license.value, loading: license.isLoading),
          const SizedBox(height: 20),
          const Text(
            'Lehrkräfte',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Jede Lehrkraft bekommt eine QR-Karte und meldet sich damit und '
            'mit ihrer eigenen PIN an. Klassen und Schüler legen die '
            'Lehrkräfte selbst an.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          ...members.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [Text(userMessage(e))],
            data: (list) {
              final teachers = list.where((m) => !m.isAdmin).toList();
              if (teachers.isEmpty) {
                return [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Noch keine Lehrkraft. Legen Sie die erste mit '
                      '„Lehrkraft anlegen“ an.',
                    ),
                  ),
                ];
              }
              return teachers
                  .map((m) => _teacherTile(context, ref, m, name))
                  .toList();
            },
          ),
        ],
      ),
    );
  }

  Widget _teacherTile(
    BuildContext context,
    WidgetRef ref,
    SchoolMember m,
    String schoolName,
  ) {
    final status = !m.cardLogin
        ? 'meldet sich mit E-Mail an'
        : m.pinSet
        ? 'Karte aktiv'
        : 'Karte noch nicht benutzt';
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEDE9FE),
          child: Icon(Icons.person, color: Colors.deepPurple),
        ),
        title: Text(m.name.isEmpty ? m.email : m.name),
        subtitle: Text(status),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'card':
                await _reissue(context, ref, m, schoolName, resetPin: false);
              case 'pin':
                await _reissue(context, ref, m, schoolName, resetPin: true);
              case 'remove':
                await _remove(context, ref, m);
            }
          },
          itemBuilder: (_) => [
            if (m.cardLogin) ...[
              const PopupMenuItem(value: 'card', child: Text('Neue Karte')),
              const PopupMenuItem(
                value: 'pin',
                child: Text('PIN zurücksetzen (neue Karte)'),
              ),
            ],
            const PopupMenuItem(
              value: 'remove',
              child: Text('Entfernen', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTeacher(
    BuildContext context,
    WidgetRef ref,
    String schoolName,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lehrkraft anlegen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'z.B. Frau Lindner',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    if (name == null || name.length < 2 || !context.mounted) return;
    await _withCard(
      context,
      () => ref.read(schoolRepositoryProvider).createTeacher(name, schoolName),
    );
  }

  Future<void> _reissue(
    BuildContext context,
    WidgetRef ref,
    SchoolMember m,
    String schoolName, {
    required bool resetPin,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(resetPin ? 'PIN zurücksetzen?' : 'Neue Karte?'),
        content: Text(
          resetPin
              ? '${m.name} bekommt eine neue Karte und legt beim ersten '
                    'Scannen eine neue PIN fest. Die alte Karte gilt nicht '
                    'mehr, angemeldete Geräte werden abgemeldet.'
              : '${m.name} bekommt eine neue Karte, die PIN bleibt. Die alte '
                    'Karte gilt nicht mehr, angemeldete Geräte werden '
                    'abgemeldet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Neue Karte'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _withCard(
      context,
      () => ref
          .read(schoolRepositoryProvider)
          .reissueTeacherCard(m, schoolName, resetPin: resetPin),
    );
  }

  Future<void> _withCard(
    BuildContext context,
    Future<TeacherCard> Function() create,
  ) async {
    try {
      final card = await create();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => TeacherCardDialog(card: card),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(e))));
      }
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    SchoolMember m,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lehrkraft entfernen?'),
        content: Text(
          '${m.name.isEmpty ? m.email : m.name} hat danach keinen Zugriff '
          'mehr. Klassen und Schüler bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(schoolRepositoryProvider).removeTeacher(m.uid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(e))));
      }
    }
  }
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.license, required this.loading});

  final DateTime? license;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final active = license != null && license!.isAfter(DateTime.now());
    final text = loading
        ? '…'
        : license == null
        ? 'Noch nicht freigeschaltet. Bitte wenden Sie sich an Lerndex.'
        : active
        ? 'Freigeschaltet bis ${_date(license!)}'
        : 'Abgelaufen am ${_date(license!)}. Bitte wenden Sie sich an Lerndex.';
    return Card(
      color: active ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
      child: ListTile(
        leading: Icon(
          active ? Icons.verified_outlined : Icons.info_outline,
          color: active ? Colors.green[700] : Colors.orange[800],
        ),
        title: const Text('Lizenz'),
        subtitle: Text(text),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// QR-Karte einer Lehrkraft groß auf dem Bildschirm, im Browser mit Drucken.
class TeacherCardDialog extends StatelessWidget {
  const TeacherCardDialog({super.key, required this.card});

  final TeacherCard card;

  @override
  Widget build(BuildContext context) {
    final qrSize = (MediaQuery.sizeOf(context).width - 140).clamp(160.0, 260.0);
    return AlertDialog(
      title: Column(
        children: [
          Text(card.name, textAlign: TextAlign.center),
          Text(
            'Lehrer-Karte',
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
              'Die Lehrkraft scannt den Code und legt beim ersten Mal ihre '
              'PIN fest. Danach meldet sie sich mit Karte und PIN an.',
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
            onPressed: () => writeHtmlToTab(openBlankTab(), teacherCardHtml(card)),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Drucken'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fertig'),
        ),
      ],
    );
  }
}
