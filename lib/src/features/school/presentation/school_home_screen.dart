import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/activity_tracker.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_screen.dart';
import '../../auth/presentation/sign_out.dart';
import '../data/school_repository.dart';
import '../domain/school_models.dart';
import 'school_class_screen.dart';
import 'school_admin_screen.dart';
import '../../../shared/user_message.dart';
import '../../../shared/legal_links.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';

/// Startseite eines reinen Schulkontos bzw. Lehrergeräts: lädt die
/// Schul-Rolle aus dem (frischen) Token und zeigt den Schulbereich – ohne
/// Elternbereich.
///
/// Im Browser (Klassen-PC) gilt die Anmeldung nur für den Tab und endet nach
/// [idleLimit] ohne Eingabe.
class SchoolRootScreen extends ConsumerStatefulWidget {
  const SchoolRootScreen({super.key});

  static const idleLimit = Duration(minutes: 30);

  @override
  ConsumerState<SchoolRootScreen> createState() => _SchoolRootScreenState();
}

class _SchoolRootScreenState extends ConsumerState<SchoolRootScreen> {
  /// Einmal pro Seite laden (nicht bei jedem build, mit Token-Erneuerung)
  late final Future<SchoolMembership?> _membership = ref
      .read(schoolRepositoryProvider)
      .membership(refresh: true);

  Timer? _idleTimer;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Auch Anmeldungen von vor dieser Einstellung (E-Mail-Login der
      // Schulleitung) nur noch im Tab halten – Firebase zieht sie um.
      ref.read(authRepositoryProvider).keepLoginInThisTabOnly();
      ActivityTracker.touch();
      _idleTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _checkIdle(),
      );
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkIdle() async {
    if (_signingOut || !ActivityTracker.idleFor(SchoolRootScreen.idleLimit)) {
      return;
    }
    _signingOut = true;
    _idleTimer?.cancel();
    final navigator = Navigator.of(context);
    await signOutAccount(ref);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(
          notice:
              'Sie wurden nach 30 Minuten ohne Eingabe abgemeldet. Bitte '
              'melden Sie sich neu an.',
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SchoolMembership?>(
      future: _membership,
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
            backgroundColor: AppColors.purple,
            foregroundColor: Colors.white,
            actions: const [SchoolLogoutAction()],
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                snap.hasError
                    ? userMessage(snap.error!)
                    : 'Dieses Konto gehört zu keiner Schule mehr. Wenn das '
                          'nicht stimmt, wenden Sie sich bitte an Ihre '
                          'Schulleitung.',
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
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        actions: [if (isRoot) const SchoolLogoutAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addClass(context, ref),
        backgroundColor: AppColors.purple,
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
            error: (e, _) => [Text(userMessage(e))],
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
                              backgroundColor: AppColors.purple.shade100,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: FittedBox(
                                  child: Text(
                                    classAvatarLabel(c.name),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.purple,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            title: Text('Klasse ${c.name}'),
                            subtitle: Text(
                              '${c.grade}. Klasse · ${c.schoolType}',
                            ),
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
          const LegalFooter(),
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
          scrollable: true,
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
    if (ok != true || name.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(schoolRepositoryProvider)
          .addClass(
            membership.schoolId,
            name: name,
            grade: grade,
            schoolType: schoolType,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userMessage(e))));
    }
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
        color: AppColors.purple,
      ),
    ),
  );
}

/// Kurzform des Klassennamens für den runden Avatar: „5b“ bleibt, aus
/// „Sonnenklasse“ wird „SO“, aus „Klasse 3 Füchse“ „3F“.
String classAvatarLabel(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  if (trimmed.length <= 3) return trimmed;
  final words = trimmed
      .split(RegExp(r'\s+'))
      .where((w) => w.toLowerCase() != 'klasse')
      .toList();
  if (words.isEmpty) return trimmed.substring(0, 2).toUpperCase();
  if (words.length == 1) {
    final w = words.first;
    return w.length <= 3 ? w : w.substring(0, 2).toUpperCase();
  }
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}
