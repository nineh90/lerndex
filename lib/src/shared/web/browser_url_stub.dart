/// Setzt den Pfad in der Adresszeile (nur im Browser).
void replaceBrowserPath(String path) {}

/// Öffnet einen leeren Tab (nur im Browser, sonst null). Muss direkt im Tipp
/// aufgerufen werden, sonst blockiert der Browser das Fenster.
Object? openBlankTab() => null;

/// Schreibt HTML in einen mit [openBlankTab] geöffneten Tab.
void writeHtmlToTab(Object? tab, String html) {}
