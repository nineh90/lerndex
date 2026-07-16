import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'src/features/auth/presentation/account_deleted_screen.dart';
import 'src/features/splash/splash_screen.dart';
// NEU: RevenueCat
import 'src/features/subscription/data/subscription_service.dart';

final accountDeletionInProgressProvider = StateProvider<bool>((ref) => false);

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // debugPrint läuft sonst auch im Release-Build und würde UIDs, Kindernamen
  // und Abo-Status ins System-Log schreiben (DSGVO). Im Release stummschalten.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // App auf Portrait-Modus beschränken
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Android: System-Photo-Picker statt eigener Galerie-Permission.
  // Pflicht laut Play-Policy (READ_MEDIA_IMAGES wurde abgelehnt) – der
  // Picker braucht keinerlei Medien-Berechtigung. Auf Android < 11 fällt
  // das Plugin automatisch auf ACTION_GET_CONTENT zurück (ebenfalls
  // permission-frei).
  final imagePicker = ImagePickerPlatform.instance;
  if (imagePicker is ImagePickerAndroid) {
    imagePicker.useAndroidPhotoPicker = true;
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // NEU: RevenueCat initialisieren (vor runApp!)
  await SubscriptionService.initialize();

  // Alle Flutter-Framework-Fehler an Crashlytics weiterleiten
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Async-Fehler die Flutter nicht selbst fängt (z.B. in Futures/Isolates)
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const ProviderScope(child: MyApp()));

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
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de', 'DE'), Locale('en', 'US')],
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
