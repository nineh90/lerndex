import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/profile_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../rewards/presentation/manage_rewards_screen.dart';
import 'live_child_stat_card.dart';
import '../../generated_tasks/presentation/improved_ai_task_generator_screen.dart';
import '../../generated_tasks/presentation/task_approval_screen.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../auth/data/auth_repository.dart';
import 'settings_screen.dart';
import '../../auth/presentation/login_screen.dart';

/// Haupt-Dashboard für Eltern mit Statistiken & Verwaltung
class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends ConsumerState<ParentDashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eltern-Dashboard'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: childrenAsync.when(
        data: (children) {
          if (children.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.child_care, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine Kinder angelegt',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tippe unten auf „Kind hinzufügen"',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fortschritte & Verwaltung',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${children.length} ${children.length == 1 ? "Kind" : "Kinder"} registriert',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                ...children.map((child) => LiveChildStatCard(childId: child.id)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Fehler: $e')),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          switch (index) {
            case 0:
              _showAddChildDialog(context);
              break;
            case 1:
              _showComingSoon(context, 'Abo');
              break;
            case 2:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
              break;
            case 3:
              _confirmSignOut(context);
              break;
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.person_add),
            label: 'Kind hinzufügen',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_outline),
            label: 'Abo',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Einstellungen',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.logout),
            label: 'Abmelden',
          ),
        ],
      ),
    );
  }

  // ── Kind hinzufügen ──────────────────────────────────────────────────────
  void _showAddChildDialog(BuildContext context) {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    int selectedGrade = 1;
    String selectedSchoolType = 'Grundschule';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Neues Kind registrieren'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ageController,
                  decoration: const InputDecoration(labelText: 'Alter'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: selectedGrade,
                  decoration: const InputDecoration(labelText: 'Klasse'),
                  items: List.generate(13, (i) => i + 1)
                      .map((g) => DropdownMenuItem(
                    value: g,
                    child: Text('Klasse $g'),
                  ))
                      .toList(),
                  onChanged: (val) => setState(() => selectedGrade = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedSchoolType,
                  decoration: const InputDecoration(labelText: 'Schulform'),
                  items: [
                    'Grundschule',
                    'Gymnasium',
                    'Realschule',
                    'Hauptschule',
                    'Gesamtschule',
                  ]
                      .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s),
                  ))
                      .toList(),
                  onChanged: (val) =>
                      setState(() => selectedSchoolType = val!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
                  );
                  try {
                    await ref.read(profileRepositoryProvider).createChild(
                      name: nameController.text,
                      age: int.tryParse(ageController.text) ?? 6,
                      grade: selectedGrade,
                      schoolType: selectedSchoolType,
                    );
                    if (context.mounted) {
                      Navigator.pop(context); // Loading
                      Navigator.pop(context); // Dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Kind erfolgreich angelegt!'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Fehler: $e'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Platzhalter „Bald verfügbar" ─────────────────────────────────────────
  void _showComingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Text(feature),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 56, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              '„$feature" ist bald verfügbar! 🚀',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Dieses Feature befindet sich gerade in Entwicklung und wird in einem zukünftigen Update freigeschaltet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  // ── Abmelden bestätigen ──────────────────────────────────────────────────
  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text('Möchtest du dich wirklich abmelden?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Dialog schließen
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
  }
}