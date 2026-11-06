import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'src/features/auth/data/child_device_repository.dart';
import 'src/features/splash/splash_screen.dart';
import 'src/shared/web/browser_url.dart';
import 'src/shared/app_links.dart';
import 'src/shared/activity_tracker.dart';
// NEU: RevenueCat
import 'src/features/subscription/data/subscription_service.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Im Browser zeigt web/index.html einen eigenen Ladebildschirm.
  if (!kIsWeb) FlutterNativeSplash.preserve(widgetsBinding: binding);

  // debugPrint läuft sonst auch im Release-Build und würde UIDs, Kindernamen
  // und Abo-Status ins System-Log schreiben (DSGVO). Im Release stummschalten.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // App auf Portrait-Modus beschränken (im Browser nicht – dort arbeiten
  // Lehrkräfte auch am PC im Querformat)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Android: System-Photo-Picker statt eigener Galerie-Permission.
  // Pflicht laut Play-Policy (READ_MEDIA_IMAGES wurde abgelehnt) – der
  // Picker braucht keinerlei Medien-Berechtigung. Auf Android < 11 fällt
  // das Plugin automatisch auf ACTION_GET_CONTENT zurück (ebenfalls
  // permission-frei).
  final imagePicker = ImagePickerPlatform.instance;
  if (imagePicker is ImagePickerAndroid) {
    imagePicker.useAndroidPhotoPicker = true;
  }

  // Lokale Emulatoren statt echter Daten (Ports wie in firebase.json):
  // flutter run --dart-define=USE_FIREBASE_EMULATOR=true
  // Start: firebase emulators:start --only auth,firestore,functions,storage
  const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

  // Im Browser greift der Auth-Emulator nicht, wenn noch eine Anmeldung
  // gespeichert ist – die Test-App spräche dann mit dem echten Firebase.
  if (useEmulator && kIsWeb) await clearStoredFirebaseLogin();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (useEmulator) {
    // Android-Emulator erreicht den Rechner unter 10.0.2.2
    final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    await FirebaseAuth.instance.useAuthEmulator(host, 19099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 18080);
    lerndexFunctions().useFunctionsEmulator(host, 15001);
    await FirebaseStorage.instance.useStorageEmulator(host, 19199);
  }

  // App Check: Der Firebase-Key steht offen in der App bzw. im Browser-
  // Quelltext. Ohne App Check könnte jeder über unser Konto Gemini aufrufen.
  // Firebase AI Logic erzwingt App Check ab 21.01.2027 (seit 02.11.2026
  // Pflicht, bis dahin auf Monitoring gestellt). firebase_ai hängt das Token
  // automatisch an jede KI-Anfrage.
  await _activateAppCheck(useEmulator: useEmulator);

  // NEU: RevenueCat initialisieren (vor runApp!)
  await SubscriptionService.initialize();

  // Crashlytics gibt es nur in den nativen Apps, nicht im Browser.
  if (!kIsWeb) {
    // Alle Flutter-Framework-Fehler an Crashlytics weiterleiten
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Async-Fehler, die Flutter nicht selbst fängt (z.B. in Futures). Die
    // App läuft danach weiter – als „nicht fatal“ melden, sonst sähe jede
    // abgebrochene Netzwerkanfrage in Crashlytics wie ein Absturz aus.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      return true;
    };
  }

  // App Link (QR-Code mit der Kamera gescannt → App öffnet sich): Pfad beim
  // Start lesen, spätere Links bei laufender App öffnen den Start neu.
  final initialLinkPath = await readInitialAppLink();
  listenForAppLinks(initialPath: initialLinkPath);

  runApp(const ProviderScope(child: MyApp()));

  if (!kIsWeb) FlutterNativeSplash.remove();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Lerndex',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de', 'DE'), Locale('en', 'US')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B21A8)),
        useMaterial3: true,
      ),
      // Im Browser am PC/Tablet: Die Oberfläche ist fürs Handy gebaut und
      // würde sonst über die ganze Breite gezogen. Eingaben zählen für die
      // Abmeldung nach Inaktivität im Schulbereich (ActivityTracker).
      builder: kIsWeb
          ? (context, child) =>
                ActivityListener(child: _WebFrame(child: child!))
          : null,
      // Der Start-Link wird nur beim ersten Aufbau mitgegeben, danach ist er
      // verbraucht (sonst würde er nach einem Neuaufbau noch einmal
      // eingelöst).
      home: LerndexSplashScreen(linkPath: takeInitialAppLink()),
    );
  }
}

/// Zentriert die App im Browser auf Handy-Breite. MediaQuery bekommt die
/// schmale Breite mit, damit Layouts, die sich an der Bildschirmbreite
/// orientieren, und auch Dialoge in den Rahmen passen.
class _WebFrame extends StatelessWidget {
  const _WebFrame({required this.child});

  final Widget child;

  static const double _maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    if (mediaQuery.size.width <= _maxWidth) return child;

    return ColoredBox(
      color: const Color(0xFF6B21A8),
      child: Center(
        child: SizedBox(
          width: _maxWidth,
          child: MediaQuery(
            data: mediaQuery.copyWith(
              size: Size(_maxWidth, mediaQuery.size.height),
            ),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}

/// App Check aktivieren: Android über Play Integrity (Debug-Builds mit
/// Debug-Token, siehe APP_CHECK_DEBUG_TOKEN), Browser über reCAPTCHA
/// Enterprise (RECAPTCHA_SITE_KEY). iOS ist noch nicht eingerichtet.
/// Ein Fehler hier darf den Start nie verhindern: Ohne Token lehnt höchstens
/// die KI Anfragen ab, sobald App Check erzwungen ist.
Future<void> _activateAppCheck({required bool useEmulator}) async {
  const recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');
  const debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');
  try {
    if (kIsWeb) {
      if (recaptchaSiteKey.isEmpty) {
        debugPrint('⚠️ App Check im Browser aus: RECAPTCHA_SITE_KEY fehlt');
        return;
      }
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaEnterpriseProvider(recaptchaSiteKey),
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      // Play Integrity klappt nur mit einer App aus dem Play Store (bzw. dem
      // internen Test-Track). Lokale Builds und der Emulator nutzen den
      // Debug-Provider; dessen Token muss in der Firebase Console unter
      // App Check → Apps → lerndex (android) → Debug-Tokens eingetragen sein.
      final debug = kDebugMode || useEmulator;
      await FirebaseAppCheck.instance.activate(
        providerAndroid: debug
            ? AndroidDebugProvider(
                debugToken: debugToken.isEmpty ? null : debugToken,
              )
            : const AndroidPlayIntegrityProvider(),
      );
    }
  } catch (e, st) {
    debugPrint('⚠️ App Check konnte nicht starten: $e');
    if (!kIsWeb) FirebaseCrashlytics.instance.recordError(e, st);
  }
}
