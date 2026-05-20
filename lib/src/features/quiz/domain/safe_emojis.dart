/// 🛡️ EMOJI-WHITELIST FÜR KINDER-QUIZFRAGEN
///
/// Strikte Allowlist: Nur diese Emojis dürfen aus dem KI-Output übernommen
/// werden. Auswahlkriterien:
///   - Eindeutig identifizierbar von Grundschulkindern (Klasse 1–4)
///   - Konsistente Darstellung auf iOS, Android & Web (kein Skin-Tone, kein
///     ZWJ-Sequence, keine flag-emojis die je nach Plattform anders aussehen)
///   - Kontextfreie Erkennung — kein „⭐ vs 🌟" Verwechslungsrisiko
///   - Keine sprachgebundenen Symbole (kein 🇩🇪 etc., das ist Politik-Quiz-Material)
///   - Keine Gesichter/Personen — Bias-frei
///
/// **Wichtig:** Diese Liste ist bewusst klein. Lieber 50 sichere Emojis als
/// 500 mit Mehrdeutigkeit. Bei Bedarf erweitern, aber jedes neue Emoji muss
/// mit Kindern getestet sein.
class SafeEmojis {
  SafeEmojis._();

  /// Kuratierte Whitelist. Geordnet nach Kategorien für bessere Wartbarkeit.
  static const Set<String> whitelist = {
    // ── Obst (zählbar, Mathe!) ────────────────────────────────────────────
    '🍎', // Apfel
    '🍌', // Banane
    '🍓', // Erdbeere
    '🍇', // Weintrauben
    '🍊', // Orange
    '🍋', // Zitrone
    '🍉', // Wassermelone
    '🍒', // Kirsche
    '🍐', // Birne
    '🥕', // Karotte

    // ── Essen ────────────────────────────────────────────────────────────
    '🍞', // Brot
    '🧀', // Käse
    '🥚', // Ei
    '🍪', // Keks
    '🍰', // Kuchen
    '🍫', // Schokolade

    // ── Tiere (eindeutig, ohne Verwechslung) ──────────────────────────────
    '🐶', // Hund
    '🐱', // Katze
    '🐭', // Maus
    '🐰', // Hase
    '🐻', // Bär
    '🐼', // Panda
    '🐮', // Kuh
    '🐷', // Schwein
    '🐸', // Frosch
    '🐔', // Huhn
    '🐧', // Pinguin
    '🐟', // Fisch
    '🦋', // Schmetterling
    '🐝', // Biene

    // ── Natur ────────────────────────────────────────────────────────────
    '🌳', // Baum
    '🌸', // Blume
    '🌻', // Sonnenblume
    '🍀', // Kleeblatt
    '☀️', // Sonne
    '🌙', // Mond
    '⭐', // Stern
    '☁️', // Wolke
    '🌧️', // Regen
    '❄️', // Schneeflocke
    '🔥', // Feuer

    // ── Gegenstände ──────────────────────────────────────────────────────
    '⚽', // Fußball
    '🎈', // Luftballon
    '🎁', // Geschenk
    '📚', // Bücher
    '✏️', // Bleistift
    '🚗', // Auto
    '🚲', // Fahrrad
    '🏠', // Haus
    '🪑', // Stuhl
    '🧸', // Teddy

    // ── Formen & Farben (für Klasse 1–2 Quiz) ──────────────────────────────
    '🔴', // roter Kreis
    '🟠', // oranger Kreis
    '🟡', // gelber Kreis
    '🟢', // grüner Kreis
    '🔵', // blauer Kreis
    '🟣', // lila Kreis
    '⚫', // schwarzer Kreis
    '⚪', // weißer Kreis
    '🟥', // rotes Quadrat
    '🟧', // oranges Quadrat
    '🟨', // gelbes Quadrat
    '🟩', // grünes Quadrat
    '🟦', // blaues Quadrat
    '🟪', // lila Quadrat
    '⬛', // schwarzes Quadrat
    '⬜', // weißes Quadrat
    '🔺', // Dreieck (rot)
    '🔻', // Dreieck (rot, unten)
  };

  /// Komma-getrennte Liste aller erlaubten Emojis — für den KI-Prompt.
  /// So weiß Gemini *exakt* aus welchem Pool gewählt werden darf.
  static String get promptList => whitelist.join(' ');

  /// Sanitisiert ein Emoji aus KI-Output:
  ///   - null/leer → null
  ///   - Nicht in Whitelist → null (Reject)
  ///   - In Whitelist → durchreichen
  ///
  /// Akzeptiert auch Fälle wo die KI mehrere Emojis liefert ("🍎🍎🍎" für
  /// "3 Äpfel") — solange JEDES einzelne in der Whitelist ist.
  static String? sanitize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Single emoji — schnellster Pfad
    if (whitelist.contains(trimmed)) return trimmed;

    // Mehrere Emojis (z.B. "🍎🍎🍎"): per Unicode-Grapheme-Iteration prüfen.
    // characters-Package wäre ideal, aber wir nutzen runes-basierte Trennung
    // mit Hilfe der Whitelist selbst — finde alle Matches.
    final matches = <String>[];
    var remainder = trimmed;
    while (remainder.isNotEmpty) {
      String? found;
      // Versuche längstes Match zuerst (manche Emojis sind mehrere Codepoints,
      // z.B. ☀️ = U+2600 U+FE0F).
      for (final emoji in whitelist) {
        if (remainder.startsWith(emoji)) {
          if (found == null || emoji.length > found.length) {
            found = emoji;
          }
        }
      }
      if (found == null) {
        // Unbekanntes Zeichen → ganze Sequenz verwerfen
        return null;
      }
      matches.add(found);
      remainder = remainder.substring(found.length);
      // Limit: Max 5 Emojis (sonst Spam)
      if (matches.length > 5) return null;
    }

    return matches.isEmpty ? null : matches.join();
  }
}
