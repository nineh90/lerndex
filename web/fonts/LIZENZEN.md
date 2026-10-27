# Ersatzschriften für die Web-Version

Flutter Web lädt Schriften für Zeichen, die in der App-Schrift fehlen (Emojis,
Symbole, Arabisch), sonst von fonts.gstatic.com. Damit der Browser der Kinder
keine Google-Server kontaktiert, liegen die Dateien hier
(`fontFallbackBaseUrl: "fonts/"` in `web/flutter_bootstrap.js`).

Die Pfade entsprechen exakt denen in Flutters `font_fallback_data.dart`.
Nach einem Flutter-Update prüfen, ob sich die Versionen (z.B. `roboto/v32`)
geändert haben. Fehlt eine Datei, zeigt die App an der Stelle ein Kästchen.

- Roboto: Apache License 2.0
- Noto Color Emoji, Noto Sans Symbols, Noto Sans Symbols 2, Noto Sans Math,
  Noto Sans Arabic, Noto Sans SC (nur das Teilstück, das die App
  im Test angefordert hat): SIL Open Font License 1.1
