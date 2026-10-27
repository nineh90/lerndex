import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check im Browser: Dort steht der Firebase-Key offen im Quelltext,
  // ohne App Check könnte jeder über unser Konto Vertex AI aufrufen.
  // firebase_ai hängt das Token automatisch an. Ohne Site-Key bleibt es aus.
  const recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');
  if (kIsWeb && recaptchaSiteKey.isNotEmpty) {
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaEnterpriseProvider(recaptchaSiteKey),
    );
  }

  // NEU: RevenueCat initialisieren (vor runApp!)
  await SubscriptionService.initialize();

  // Crashlytics gibt es nur in den nativen Apps, nicht im Browser.
  if (!kIsWeb) {
    // Alle Flutter-Framework-Fehler an Crashlytics weiterleiten
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Async-Fehler die Flutter nicht selbst fängt (z.B. in Futures/Isolates)
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runApp(const ProviderScope(child: MyApp()));

  if (!kIsWeb) FlutterNativeSplash.remove();
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
      // Im Browser am PC/Tablet: Die Oberfläche ist fürs Handy gebaut und
      // würde sonst über die ganze Breite gezogen.
      builder: kIsWeb ? (context, child) => _WebFrame(child: child!) : null,
      home: isDeletingAccount
          ? const AccountDeletedScreen()
          : const LerndexSplashScreen(),
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
