import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Setzt den Pfad in der Adresszeile, ohne neuen Verlaufseintrag.
void replaceBrowserPath(String path) {
  web.window.history.replaceState(null, '', path);
}

/// Öffnet einen leeren Tab. Muss direkt im Tipp aufgerufen werden, sonst
/// blockiert der Browser das Fenster.
Object? openBlankTab() => web.window.open('', '_blank');

/// Schreibt HTML in einen mit [openBlankTab] geöffneten Tab.
void writeHtmlToTab(Object? tab, String html) {
  if (tab == null) return;
  // tab kommt immer aus openBlankTab
  (tab as web.Window).document
    ..open()
    ..write(html.toJS)
    ..close();
}

/// Nur für den Emulator-Modus: gespeicherte Firebase-Anmeldung löschen,
/// bevor Firebase startet. Liegt dort eine Anmeldung, greift die Umstellung
/// auf den Auth-Emulator nicht – die Test-App liefe dann still gegen das
/// echte Firebase.
Future<void> clearStoredFirebaseLogin() async {
  final done = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase('firebaseLocalStorageDb');
  void finish(web.Event _) {
    if (!done.isCompleted) done.complete();
  }

  request.onsuccess = finish.toJS;
  request.onerror = finish.toJS;
  request.onblocked = finish.toJS;
  await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
}
