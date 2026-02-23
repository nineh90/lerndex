import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Auth
import 'src/features/auth/presentation/login_screen.dart';
import 'src/features/auth/presentation/onboarding_screen.dart';
import 'src/features/auth/presentation/active_child_provider.dart';
import 'src/features/auth/presentation/family_dashboard_screen.dart';
import 'src/features/auth/data/auth_repository.dart';

// Schüler-Dashboard
import 'src/features/student_dashboard/presentation/student_dashboard_screen.dart';

// ============================================================================
// GLOBALER PROVIDER: Account-Löschung läuft
// Verhindert dass MyApp während der Löschung auf authStateChanges reagiert
// ============================================================================
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

    // Wenn Account gerade gelöscht wird → statischen Screen zeigen
    // NICHT auf authStateChanges reagieren, das würde den Crash verursachen
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
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, st) => Scaffold(body: Center(child: Text('Fehler: $e'))),
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
            body: Center(child: CircularProgressIndicator()),
          );
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

// ============================================================================
// ÜBERGANGS-SCREEN NACH ACCOUNT-LÖSCHUNG
// Kein ConsumerWidget! Watched keine Provider.
// ============================================================================
class AccountDeletedScreen extends StatefulWidget {
  const AccountDeletedScreen({super.key});

  @override
  State<AccountDeletedScreen> createState() => _AccountDeletedScreenState();
}

class _AccountDeletedScreenState extends State<AccountDeletedScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        // Flag zurücksetzen
        ProviderScope.containerOf(
          context,
        ).read(accountDeletionInProgressProvider.notifier).state = false;

        // Direkt zum LoginScreen navigieren und Stack leeren
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Konto wurde gelöscht',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Du wirst zum Login weitergeleitet...'),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
