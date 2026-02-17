import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// Imports für Auth-System
import 'src/features/auth/presentation/login_screen.dart';
import 'src/features/auth/presentation/active_child_provider.dart';
import 'src/features/auth/data/auth_repository.dart';
import 'src/features/auth/data/profile_repository.dart';
import 'src/features/auth/domain/child_model.dart';

// Import für Quiz-System
import 'src/features/quiz/presentation/quiz_screen.dart';
import 'src/features/quiz/data/extended_quiz_repository.dart';

// Imports für Eltern-Dashboard
import 'src/features/parent_dashboard/presentation/parent_dashboard_screen.dart';
import 'src/features/parent_dashboard/presentation/pin_setup_dialog.dart';
import 'src/features/parent_dashboard/presentation/pin_input_dialog.dart';
import 'src/features/parent_dashboard/data/pin_repository.dart';

// Imports für Belohnungssystem
import 'src/features/rewards/presentation/rewards_screen.dart';

// Import KI-Tutor
import 'src/features/tutor/presentation/tutor_screen.dart';

// ✅ NEU: Schüler-Dashboard mit Bottom App Bar
import 'src/features/student_dashboard/presentation/student_dashboard_screen.dart';

import 'src/features/generated_tasks/data/generated_task_models.dart';
import 'src/features/generated_tasks/data/generated_task_repository.dart';
import 'src/features/generated_tasks/data/firebase_ai_service_improved.dart';
import 'src/features/generated_tasks/presentation/improved_ai_task_generator_screen.dart';
import 'src/features/generated_tasks/presentation/task_approval_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final activeChild = ref.watch(activeChildProvider);

    return MaterialApp(
      title: 'Lerndex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: authState.when(
        data: (user) {
          if (user == null) return const LoginScreen();
          // ✅ Neues Schüler-Dashboard statt altem ChildDashboard
          if (activeChild != null) return const StudentDashboardScreen();
          return const ParentAdminDashboard();
        },
        loading: () =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, st) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      ),
    );
  }
}

// ============================================================================
// ELTERN-ADMIN-DASHBOARD (Kind-Auswahl)
// ============================================================================

class ParentAdminDashboard extends ConsumerWidget {
  const ParentAdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenAsync = ref.watch(childrenListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lerndex Admin'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () async => await _openParentDashboard(context, ref),
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: 'Eltern-Dashboard',
          ),
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
          ),
        ],
      ),
      body: childrenAsync.when(
        data: (children) {
          if (children.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.child_care, size: 100, color: Colors.grey[400]),
                  const SizedBox(height: 20),
                  Text(
                    'Noch keine Kinder angelegt',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 10),
                  const Text('Füge dein erstes Kind hinzu!'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: children.length,
            itemBuilder: (context, index) {
              final child = children[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.deepPurple.shade100,
                    child: Text(
                      child.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                  title: Text(
                    child.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text('${child.schoolType} • Klasse ${child.grade}'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.stars,
                              size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text('${child.stars}'),
                          const SizedBox(width: 16),
                          const Icon(Icons.emoji_events,
                              size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text('Level ${child.level}'),
                        ],
                      ),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 110,
                    child: ElevatedButton(
                      onPressed: () =>
                          ref.read(activeChildProvider.notifier).select(child),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, size: 14),
                          SizedBox(width: 3),
                          Text('Lernen', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Fehler: $e')),
      ),
    );
  }

  Future<void> _openParentDashboard(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    final hasPin = await ref.read(pinRepositoryProvider).hasPinSet(user.uid);

    if (!hasPin) {
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PinSetupDialog(),
      );
      if (created != true) return;
    }

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PinInputDialog(),
    );

    if (verified == true && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
      );
    }
  }
}