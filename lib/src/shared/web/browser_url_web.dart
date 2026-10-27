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
