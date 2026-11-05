import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/auth/data/child_device_repository.dart';
import '../features/school/data/parent_link_repository.dart';
import '../features/school/data/school_repository.dart';
import '../features/splash/splash_screen.dart';
import 'web/browser_url.dart';

// ============================================================================
// LERNDEX-LINKS IN DER APP
//
// Im Browser liest der Startbildschirm den Pfad aus der Adresszeile
// (…/k/CODE, …/s/TOKEN usw.). In der Android-App kommen dieselben Links als
// App Link (Kamera scannt den QR-Code, Android öffnet die App) oder über den
// QR-Scanner in der App. Beide landen hier und starten den Startbildschirm
// mit dem Pfad neu, der Rest läuft wie im Browser.
// ============================================================================

/// Navigator der App, damit ein Link von außen den Startbildschirm öffnen kann.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Hosts, unter denen die Web-App läuft (alte Links zeigen noch auf web.app).
const _lerndexHosts = {
  'app.lerndex.de',
  'lerndex-3775f.web.app',
  'lerndex-3775f.firebaseapp.com',
};

/// Pfad eines Lerndex-Links, den der Startbildschirm versteht, sonst null.
/// Nimmt auch einen Text aus dem QR-Scanner (mit oder ohne https://).
String? lerndexLinkPath(String raw) {
  var text = raw.trim();
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !_lerndexHosts.contains(uri.host.toLowerCase())) {
    return null;
  }
  return knownLinkPath(uri.path);
}

/// [path], wenn der Startbildschirm ihn versteht (…/k/CODE usw.), sonst null.
String? knownLinkPath(String path) {
  final known =
      pairingCodeFromPath(path) ??
      studentCardFromPath(path) ??
      teacherCardFromPath(path) ??
      parentLinkCodeFromPath(path) ??
      schoolSignupFromPath(path);
  return known == null ? null : path;
}

/// Öffnet den Startbildschirm mit einem Link-Pfad und räumt alles andere ab.
void openLinkPath(String path) {
  appNavigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => LerndexSplashScreen(linkPath: path)),
    (_) => false,
  );
}

String? _initialLinkPath;

/// Link, mit dem die App gestartet wurde (Pfad), oder null. Merkt ihn sich
/// für [takeInitialAppLink].
///
/// Im Browser hat web/index.html den Pfad schon vor dem Start aus der
/// Adresszeile genommen (Codes sollen nicht im Verlauf bleiben). Ging das
/// nicht, steht er noch in der Adresszeile.
Future<String?> readInitialAppLink() async {
  if (kIsWeb) {
    _initialLinkPath = knownLinkPath(takeStoredLinkPath() ?? Uri.base.path);
    if (_initialLinkPath != null) replaceBrowserPath('/');
    return _initialLinkPath;
  }
  try {
    final uri = await AppLinks().getInitialLink().timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    _initialLinkPath = uri == null ? null : lerndexLinkPath(uri.toString());
  } catch (e) {
    debugPrint('⚠️ App Link beim Start nicht lesbar: $e');
  }
  return _initialLinkPath;
}

/// Gibt den Start-Link genau einmal heraus, danach null.
String? takeInitialAppLink() {
  final path = _initialLinkPath;
  _initialLinkPath = null;
  return path;
}

/// Nur Android/iOS: Links, die bei laufender App ankommen, öffnen den
/// Startbildschirm neu. [initialPath] wurde schon beim Start verarbeitet;
/// das Plugin liefert ihn im Stream noch einmal, das erste Mal wird er
/// deshalb übersprungen.
StreamSubscription<Uri>? listenForAppLinks({String? initialPath}) {
  if (kIsWeb) return null;
  var skipInitial = initialPath != null;
  return AppLinks().uriLinkStream.listen((uri) {
    final path = lerndexLinkPath(uri.toString());
    if (skipInitial) {
      skipInitial = false;
      if (path == initialPath) return;
    }
    if (path != null) openLinkPath(path);
  }, onError: (Object e) => debugPrint('⚠️ App Link: $e'));
}
