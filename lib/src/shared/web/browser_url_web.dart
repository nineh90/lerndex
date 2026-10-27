import 'package:web/web.dart' as web;

/// Setzt den Pfad in der Adresszeile, ohne neuen Verlaufseintrag.
void replaceBrowserPath(String path) {
  web.window.history.replaceState(null, '', path);
}
