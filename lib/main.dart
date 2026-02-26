import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'src/features/auth/presentation/login_screen.dart';
import 'src/features/auth/presentation/onboarding_screen.dart';
import 'src/features/auth/presentation/family_dashboard_screen.dart';
import 'src/features/auth/data/auth_repository.dart';
import 'src/features/auth/presentation/account_deleted_screen.dart';

final accountDeletionInProgressProvider = StateProvider<bool>((ref) => false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDeletingAccount = ref.watch(accountDeletionInProgressProvider);

    if (isDeletingAccount) {
      return MaterialApp(
        title: 'Lerndex',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B21A8)),
          useMaterial3: true,
        ),
        home: const AccountDeletedScreen(),
      );
    }

    final authState = ref.watch(authStateChangesProvider);

    return MaterialApp(
      title: 'Lerndex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B21A8)),
        useMaterial3: true,
      ),
      home: authState.when(
        data: (user) {
          if (user == null) return const LoginScreen();
          return const _OnboardingGate();
        },
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, st) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      ),
    );
  }
}

/// Prüft Onboarding, dann zeigt FamilyDashboard.
/// Die Navigation zum StudentDashboard übernimmt FamilyDashboardScreen selbst.
class _OnboardingGate extends ConsumerWidget {
  const _OnboardingGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: ref.read(authRepositoryProvider).isOnboardingComplete(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == true
            ? const FamilyDashboardScreen()
            : const OnboardingScreen();
      },
    );
  }
}
