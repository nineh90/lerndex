import 'package:flutter/foundation.dart';

// Plattform-Abfragen, die auch im Browser funktionieren. `Platform.isIOS` aus
// dart:io wirft im Web einen Fehler.

/// Native iOS-App. Safari auf dem iPhone zählt nicht dazu.
bool get isIOSApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// 'web', 'ios' oder 'android' – für Feedback-Mails und Logs.
String get platformName {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}
