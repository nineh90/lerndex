/// 🧩 REINE PARSING-LOGIK FÜR KI-ANTWORTEN
///
/// Diese Klasse bündelt alle *reinen* String-/JSON-Transformationen, die auf
/// dem KI-Output (Vertex AI / Gemini) ausgeführt werden. Sie ist bewusst frei
/// von Firebase-, Riverpod- oder UI-Abhängigkeiten, damit die Logik isoliert
/// unit-getestet werden kann.
///
/// Quelle der Wahrheit für:
///   - Tutor-Tags `[FACH:...]` und `[KORREKT:ja/nein]`
///   - Bild-Platzhalter-Bereinigung im Fragetext (früher dupliziert in
///     `question_model.dart` und `vertex_ai_service.dart`)
///   - JSON-Reparatur (Markdown-Fences, nackte Emojis, Newlines in Strings)
class AiResponseParser {
  AiResponseParser._();

  // ── Tutor-Tags ─────────────────────────────────────────────────────────────

  /// Extrahiert das vom Tutor erkannte Schulfach aus `[FACH:...]`.
  /// Gibt `'kein_schulfach'` zurück wenn kein Tag vorhanden ist.
  static String extractSubjectTag(String response) {
    final match = RegExp(r'\[FACH:([^\]]+)\]').firstMatch(response);
    if (match == null) return 'kein_schulfach';
    return match.group(1)?.trim() ?? 'kein_schulfach';
  }

  /// Bestimmt ob die Kind-Antwort korrekt war.
  ///
  /// Priorität:
  ///   1. Expliziter Tag `[KORREKT:ja|nein]` (case-insensitive).
  ///   2. Heuristische Textanalyse (eindeutig-falsch vor eindeutig-richtig).
  ///   3. Kein klares Signal → `false` ("sicher ist sicher", kein XP).
  static bool extractCorrectTag(String response) {
    // 1. Expliziter KI-Tag hat höchste Priorität
    final match = RegExp(
      r'\[KORREKT:(ja|nein)\]',
      caseSensitive: false,
    ).firstMatch(response);
    if (match != null) {
      return match.group(1)?.toLowerCase() != 'nein';
    }

    // 2. Lokale Textanalyse der KI-Antwort
    final lower = response.toLowerCase();

    // Eindeutig falsch
    const wrongPhrases = [
      'leider falsch',
      'leider nicht richtig',
      'leider nicht korrekt',
      'das ist falsch',
      'das ist leider',
      'nicht ganz richtig',
      'fast richtig',
      'nicht ganz',
      'nicht korrekt',
      'leider nicht',
      'das stimmt leider',
      'das ist nicht richtig',
      'das ist nicht korrekt',
      'das war nicht',
      'falsche antwort',
      'noch nicht ganz',
      'nicht die richtige',
      'nicht die richtige antwort',
      'not quite',
      'not correct',
      "that's not",
      'almost',
      'unfortunately',
      'wrong',
      'incorrect',
    ];
    if (wrongPhrases.any((p) => lower.contains(p))) return false;

    // Eindeutig richtig
    const correctPhrases = [
      'richtig',
      'korrekt',
      'genau',
      'super',
      'toll',
      'prima',
      'klasse',
      'bravo',
      'perfekt',
      'wunderbar',
      'sehr gut',
      'gut gemacht',
      'das stimmt',
      'das ist richtig',
      'correct',
      'exactly',
      'well done',
      'great',
      'perfect',
      'excellent',
      "that's right",
    ];
    if (correctPhrases.any((p) => lower.contains(p))) return true;

    // Kein klares Signal → kein XP (sicher ist sicher)
    return false;
  }

  /// Entfernt FACH- und KORREKT-Tags inkl. aller Label-Varianten aus der
  /// Tutor-Antwort, bevor sie dem Kind angezeigt wird.
  static String stripTutorTags(String response) {
    return response
        // FACH mit optionalem Label-Praefix
        .replaceAll(
          RegExp(
            r'[-–]?\s*(?:Erkanntes\s+)?Schulfach:\s*\[FACH:[^\]]*\]',
            caseSensitive: false,
          ),
          '',
        )
        // Nackter FACH-Tag
        .replaceAll(RegExp(r'\s*\[FACH:[^\]]*\]', caseSensitive: false), '')
        // "KORREKT: [ja]" oder "KORREKT: [nein]" (mit Leerzeichen vor Klammer)
        .replaceAll(
          RegExp(r'\s*KORREKT:\s*\[[^\]]*\]', caseSensitive: false),
          '',
        )
        // Nackter [KORREKT:ja/nein]-Tag (ohne Leerzeichen)
        .replaceAll(RegExp(r'\s*\[KORREKT:[^\]]*\]', caseSensitive: false), '')
        // Leerzeilen aufraeumen
        .replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n')
        .trim();
  }

  // ── Bild-Platzhalter ────────────────────────────────────────────────────────

  /// Entfernt Klammer-Platzhalter wie "(Bild eines Apfels)", "[Bild: Hund]"
  /// oder "(siehe Bild)" aus dem Fragetext. Diese kamen früher von der KI,
  /// wenn das Modell ein Bild "wollte" aber keines liefern konnte. Heute wird
  /// stattdessen das `emoji`-Feld genutzt.
  static String stripImagePlaceholders(String text) {
    final patterns = [
      RegExp(r'\(\s*Bild[^)]*\)', caseSensitive: false),
      RegExp(r'\[\s*Bild[^\]]*\]', caseSensitive: false),
      RegExp(r'\(\s*siehe Bild[^)]*\)', caseSensitive: false),
      RegExp(r'\(\s*Image[^)]*\)', caseSensitive: false),
      RegExp(r'\[\s*Image[^\]]*\]', caseSensitive: false),
    ];
    var cleaned = text;
    for (final p in patterns) {
      cleaned = cleaned.replaceAll(p, '');
    }
    // Doppelte Leerzeichen + Whitespace bereinigen
    return cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  // ── JSON-Reparatur ──────────────────────────────────────────────────────────

  /// Bereinigt KI-JSON-Output: entfernt Markdown-Fences (```json … ```),
  /// repariert Newlines in Strings und nackte Emoji-Werte.
  static String cleanJson(String text) {
    String cleaned = text.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();
    return quoteBareEmoji(fixJsonNewlines(cleaned));
  }

  /// Repariert einen häufigen KI-Fehler: der emoji-Wert wird ohne
  /// Anführungszeichen geliefert, was das ganze JSON-Array unparsbar macht:
  ///   "emoji": ☀️,        →   "emoji": "☀️",
  ///   "emoji": 🍎🍎🍎,     →   "emoji": "🍎🍎🍎",
  /// Bereits korrekt gequotete Werte und `null` werden nicht angefasst.
  static String quoteBareEmoji(String json) {
    final re = RegExp(r'("emoji"\s*:\s*)(?!"|null\b)([^"\s,}\]]+)');
    return json.replaceAllMapped(re, (m) => '${m[1]}"${m[2]}"');
  }

  /// Ersetzt rohe Zeilenumbrüche *innerhalb* von JSON-Strings durch `\n`
  /// (bzw. verwirft `\r`), damit das Ergebnis valides JSON ist. Umbrüche
  /// außerhalb von Strings bleiben unangetastet.
  static String fixJsonNewlines(String json) {
    final buffer = StringBuffer();
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < json.length; i++) {
      final char = json[i];
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == '\\' && inString) {
        buffer.write(char);
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        buffer.write(char);
        continue;
      }
      if (inString && char == '\n') {
        buffer.write('\\n');
        continue;
      }
      if (inString && char == '\r') {
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }
}
