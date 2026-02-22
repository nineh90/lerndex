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
import 'src/features/auth/presentation/family_dashboard_screen.dart';
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
/// Falls nicht → OnboardingScreen, sonst → FamilyDashboardScreen
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

        return const FamilyDashboardScreen();
      },
    );
  }
}