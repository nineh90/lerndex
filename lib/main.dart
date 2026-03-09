import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'src/features/auth/presentation/account_deleted_screen.dart';
import 'src/features/splash/splash_screen.dart';

final accountDeletionInProgressProvider = StateProvider<bool>((ref) => false);

void main() async {
  // Native Splash so lange anzeigen bis Flutter bereit ist.
  // Ohne preserve() wird er sofort beim ersten Frame entfernt.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Alle Flutter-Framework-Fehler an Crashlytics weiterleiten
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Async-Fehler die Flutter nicht selbst fängt (z.B. in Futures/Isolates)
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const ProviderScope(child: MyApp()));

  // Native Splash jetzt entfernen – Flutter-Splash übernimmt nahtlos.
  FlutterNativeSplash.remove();
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDeletingAccount = ref.watch(accountDeletionInProgressProvider);

    return MaterialApp(
      title: 'Lerndex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B21A8)),
        useMaterial3: true,
      ),
      home: isDeletingAccount
          ? const AccountDeletedScreen()
          : const LerndexSplashScreen(),
    );
  }
}
