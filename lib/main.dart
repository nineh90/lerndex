import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// Auth
import 'src/features/auth/presentation/login_screen.dart';
import 'src/features/auth/presentation/onboarding_screen.dart';
import 'src/features/auth/presentation/active_child_provider.dart';
import 'src/features/auth/data/auth_repository.dart';
import 'src/features/auth/data/profile_repository.dart';
import 'src/features/auth/domain/child_model.dart';

// Quiz
import 'src/features/quiz/presentation/quiz_screen.dart';
import 'src/features/quiz/data/extended_quiz_repository.dart';

// Eltern-Dashboard
import 'src/features/parent_dashboard/presentation/parent_dashboard_screen.dart';
import 'src/features/parent_dashboard/presentation/pin_setup_dialog.dart';
import 'src/features/parent_dashboard/presentation/pin_input_dialog.dart';
import 'src/features/parent_dashboard/data/pin_repository.dart';

// Belohnungen
import 'src/features/rewards/presentation/rewards_screen.dart';

// KI-Tutor
import 'src/features/tutor/presentation/tutor_screen.dart';

// Schüler-Dashboard
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B21A8)),
        useMaterial3: true,
      ),
      home: authState.when(
        data: (user) {
          // Nicht eingeloggt → Login
          if (user == null) return const LoginScreen();

          // Kind aktiv → Schüler-Dashboard
          if (activeChild != null) return const StudentDashboardScreen();

          // Eingeloggt → Onboarding-Check
          return _OnboardingGate();
        },
        loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator())),
        error: (e, st) =>
            Scaffold(body: Center(child: Text('Fehler: $e'))),
      ),
    );
  }
}

/// Prüft ob Onboarding abgeschlossen ist.
/// Falls nicht → OnboardingScreen, sonst → ParentAdminDashboard
class _OnboardingGate extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: ref.read(authRepositoryProvider).isOnboardingComplete(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final onboardingDone = snapshot.data ?? false;

        if (!onboardingDone) {
          return const OnboardingScreen();
        }

        return const ParentAdminDashboard();
      },
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
        title: const Text('Lerndex'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Eltern-Dashboard',
            onPressed: () => _openParentDashboard(context, ref),
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
                  const Icon(Icons.child_care,
                      size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Noch keine Kinder angelegt',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text(
                      'Öffne das Eltern-Dashboard um ein Kind hinzuzufügen',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _openParentDashboard(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Kind hinzufügen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B21A8),
                      foregroundColor: Colors.white,
                    ),
                  ),
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
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF6B21A8),
                    radius: 24,
                    child: Text(
                      child.name[0].toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(child.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
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
                      onPressed: () => ref
                          .read(activeChildProvider.notifier)
                          .select(child),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, size: 14),
                          SizedBox(width: 3),
                          Text('Lernen',
                              style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () =>
        const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Fehler: $e')),
      ),
    );
  }

  Future<void> _openParentDashboard(
      BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    final hasPin =
    await ref.read(pinRepositoryProvider).hasPinSet(user.uid);

    if (!hasPin) {
      // Sollte nach dem Onboarding nicht mehr vorkommen, aber als Fallback
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
        MaterialPageRoute(
            builder: (_) => const ParentDashboardScreen()),
      );
    }
  }
}