import 'dart:math';

import 'package:flutter/material.dart';

// ============================================================================
// LETTER TASK ENGINE – Algorithmischer Generator für Klasse 1 & 2 (Buchstaben)
//
// Kein KI, kein Firebase, keine Duplikate.
// Aufgaben skalieren mit dem Level des Kindes.
//
// 5 feste Slots je Runde (immer alle 5 Typen, zufällig gemischt):
//
// Stufe 1 (Lvl  1– 3): anlaut | grossKlein | bildWort | buchstabeMalen | reihenfolge
// Stufe 2 (Lvl  4– 7): anlaut | grossKlein | bildWort | buchstabeMalen | reim
// Stufe 3 (Lvl  8–12): anlaut | grossKlein | bildWort | buchstabeMalen | wortlaenge
// Stufe 4 (Lvl 13–20): anlaut | grossKlein | bildWort | buchstabeMalen | wortlaenge
// Stufe 5 (Lvl 21+  ): anlaut | grossKlein | bildWort | buchstabeMalen | wortlaenge
//
// Aufgabentypen:
//   anlaut       – Welcher Buchstabe beginnt das Bild?  🐸 → F, G, H, T
//   grossKlein   – A gehört zu welchem Kleinbuchstaben? → a b c d
//   bildWort     – 🐱 → K_TZE, welcher Buchstabe fehlt?
//   buchstabeMalen – Male den Buchstaben (Vertex AI prüft)
//   reihenfolge  – A, B, __, D → welcher fehlt?
//   reim         – Was reimt auf „Haus"? → Maus / Baum / Hund / Schuh
//   wortlaenge   – Welches Wort ist länger?
// ============================================================================

enum LetterTaskType {
  anlaut, // Welcher Buchstabe beginnt das Bild?
  grossKlein, // Großbuchstabe → passender Kleinbuchstabe
  bildWort, // Bild → Wort mit Lücke, Buchstabe finden
  buchstabeMalen, // Buchstabe malen, KI prüft
  reihenfolge, // A B __ D → fehlender Buchstabe
  reim, // Was reimt auf X?
  wortlaenge, // Welches Wort ist länger/kürzer?
}

// ── Aufgaben-Modell ───────────────────────────────────────────────────────────

class LetterTask {
  final LetterTaskType type;

  /// Haupt-Fragetext (auch für TTS)
  final String questionText;

  /// Emoji/Bild das zur Frage gehört (für anlaut, bildWort)
  final String? emoji;

  /// Antwortoptionen
  final List<String> options;

  /// Korrekte Antwort
  final String correctAnswer;

  /// Feedback
  final String feedbackCorrect;
  final String feedbackWrong;

  /// Schwierigkeitsstufe (1–5)
  final int difficultyLevel;

  /// Für bildWort: Das vollständige Wort und der Index des fehlenden Buchstabens
  final String? fullWord;
  final int? missingIndex;

  /// Für buchstabeMalen: der zu malende Buchstabe
  final String? letterToDraw;

  /// Für reihenfolge: die Buchstabenfolge mit Lücke
  final List<String>? letterSequence;
  final int? blankIndex;

  /// Für wortlaenge: die zwei Wörter zum Vergleichen
  final String? wordA;
  final String? wordB;

  const LetterTask({
    required this.type,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    required this.feedbackCorrect,
    required this.feedbackWrong,
    required this.difficultyLevel,
    this.emoji,
    this.fullWord,
    this.missingIndex,
    this.letterToDraw,
    this.letterSequence,
    this.blankIndex,
    this.wordA,
    this.wordB,
  });
}

// ── Daten-Pool ────────────────────────────────────────────────────────────────

/// Emoji → {anlaut, wort}
/// Alle Einträge geprüft: Emoji eindeutig erkennbar, deutsches Wort,
/// Anlaut == erster Buchstabe des Wortes, Wort Erstklässlern bekannt.
const _emojiData = [
  // A – 5 Einträge
  {'emoji': '🍎', 'anlaut': 'A', 'wort': 'APFEL'},
  {'emoji': '🐜', 'anlaut': 'A', 'wort': 'AMEISE'},
  {'emoji': '🦅', 'anlaut': 'A', 'wort': 'ADLER'},
  {'emoji': '🚗', 'anlaut': 'A', 'wort': 'AUTO'},
  {'emoji': '🐊', 'anlaut': 'A', 'wort': 'ALLIGATOR'},
  // B – 7 Einträge
  {'emoji': '🐝', 'anlaut': 'B', 'wort': 'BIENE'},
  {'emoji': '🐻', 'anlaut': 'B', 'wort': 'BAER'},
  {'emoji': '🌸', 'anlaut': 'B', 'wort': 'BLUME'},
  {'emoji': '🍌', 'anlaut': 'B', 'wort': 'BANANE'},
  {'emoji': '🍐', 'anlaut': 'B', 'wort': 'BIRNE'},
  {'emoji': '⚽', 'anlaut': 'B', 'wort': 'BALL'},
  {'emoji': '📚', 'anlaut': 'B', 'wort': 'BUCH'},
  // D – 3 Einträge
  {'emoji': '🐬', 'anlaut': 'D', 'wort': 'DELFIN'},
  {'emoji': '🐉', 'anlaut': 'D', 'wort': 'DRACHE'},
  {'emoji': '💎', 'anlaut': 'D', 'wort': 'DIAMANT'},
  // E – 5 Einträge
  {'emoji': '🐘', 'anlaut': 'E', 'wort': 'ELEFANT'},
  {'emoji': '🦆', 'anlaut': 'E', 'wort': 'ENTE'},
  {'emoji': '🥚', 'anlaut': 'E', 'wort': 'EI'},
  {'emoji': '🍦', 'anlaut': 'E', 'wort': 'EIS'},
  {'emoji': '🫏', 'anlaut': 'E', 'wort': 'ESEL'},
  // F – 5 Einträge
  {'emoji': '🐸', 'anlaut': 'F', 'wort': 'FROSCH'},
  {'emoji': '🦊', 'anlaut': 'F', 'wort': 'FUCHS'},
  {'emoji': '🐟', 'anlaut': 'F', 'wort': 'FISCH'},
  {'emoji': '🦩', 'anlaut': 'F', 'wort': 'FLAMINGO'},
  {'emoji': '🦋', 'anlaut': 'F', 'wort': 'FALTER'},
  // G – 4 Einträge
  {'emoji': '🦒', 'anlaut': 'G', 'wort': 'GIRAFFE'},
  {'emoji': '🐐', 'anlaut': 'G', 'wort': 'GEISS'},
  {'emoji': '🎸', 'anlaut': 'G', 'wort': 'GITARRE'},
  {'emoji': '🌿', 'anlaut': 'G', 'wort': 'GRAS'},
  // H – 6 Einträge
  {'emoji': '🐹', 'anlaut': 'H', 'wort': 'HAMSTER'},
  {'emoji': '🏠', 'anlaut': 'H', 'wort': 'HAUS'},
  {'emoji': '🐇', 'anlaut': 'H', 'wort': 'HASE'},
  {'emoji': '🐓', 'anlaut': 'H', 'wort': 'HAHN'},
  {'emoji': '🍯', 'anlaut': 'H', 'wort': 'HONIG'},
  {'emoji': '🐴', 'anlaut': 'H', 'wort': 'HUT'},
  // I – 2 Einträge
  {'emoji': '🦔', 'anlaut': 'I', 'wort': 'IGEL'},
  {'emoji': '🏝️', 'anlaut': 'I', 'wort': 'INSEL'},
  // K – 7 Einträge
  {'emoji': '🐱', 'anlaut': 'K', 'wort': 'KATZE'},
  {'emoji': '🦘', 'anlaut': 'K', 'wort': 'KAENGURU'},
  {'emoji': '🐄', 'anlaut': 'K', 'wort': 'KUH'},
  {'emoji': '🍒', 'anlaut': 'K', 'wort': 'KIRSCHE'},
  {'emoji': '👑', 'anlaut': 'K', 'wort': 'KRONE'},
  {'emoji': '🧀', 'anlaut': 'K', 'wort': 'KAESE'},
  {'emoji': '🐊', 'anlaut': 'K', 'wort': 'KROKODIL'},
  // L – 3 Einträge
  {'emoji': '🦁', 'anlaut': 'L', 'wort': 'LOEWE'},
  {'emoji': '🚂', 'anlaut': 'L', 'wort': 'LOKOMOTIVE'},
  {'emoji': '🌼', 'anlaut': 'L', 'wort': 'LOEWENZAHN'},
  // M – 5 Einträge
  {'emoji': '🐭', 'anlaut': 'M', 'wort': 'MAUS'},
  {'emoji': '🌙', 'anlaut': 'M', 'wort': 'MOND'},
  {'emoji': '🦟', 'anlaut': 'M', 'wort': 'MUECKE'},
  {'emoji': '🥛', 'anlaut': 'M', 'wort': 'MILCH'},
  {'emoji': '🐒', 'anlaut': 'M', 'wort': 'MEERKATZE'},
  // N – 3 Einträge
  {'emoji': '🦏', 'anlaut': 'N', 'wort': 'NASHORN'},
  {'emoji': '🌃', 'anlaut': 'N', 'wort': 'NACHT'},
  {'emoji': '🪆', 'anlaut': 'N', 'wort': 'NUSS'},
  // O – 3 Einträge
  {'emoji': '🍊', 'anlaut': 'O', 'wort': 'ORANGE'},
  {'emoji': '🦦', 'anlaut': 'O', 'wort': 'OTTER'},
  {'emoji': '🫒', 'anlaut': 'O', 'wort': 'OLIVE'},
  // P – 5 Einträge
  {'emoji': '🐧', 'anlaut': 'P', 'wort': 'PINGUIN'},
  {'emoji': '🦜', 'anlaut': 'P', 'wort': 'PAPAGEI'},
  {'emoji': '🐴', 'anlaut': 'P', 'wort': 'PFERD'},
  {'emoji': '🍕', 'anlaut': 'P', 'wort': 'PIZZA'},
  {'emoji': '🦚', 'anlaut': 'P', 'wort': 'PFAU'},
  // R – 4 Einträge
  {'emoji': '🌹', 'anlaut': 'R', 'wort': 'ROSE'},
  {'emoji': '🦌', 'anlaut': 'R', 'wort': 'RENTIER'},
  {'emoji': '🐀', 'anlaut': 'R', 'wort': 'RATTE'},
  {'emoji': '🚀', 'anlaut': 'R', 'wort': 'RAKETE'},
  // S – 8 Einträge
  {'emoji': '🐍', 'anlaut': 'S', 'wort': 'SCHLANGE'},
  {'emoji': '⭐', 'anlaut': 'S', 'wort': 'STERN'},
  {'emoji': '🌞', 'anlaut': 'S', 'wort': 'SONNE'},
  {'emoji': '🐢', 'anlaut': 'S', 'wort': 'SCHILDKROETE'},
  {'emoji': '🕷️', 'anlaut': 'S', 'wort': 'SPINNE'},
  {'emoji': '🦢', 'anlaut': 'S', 'wort': 'SCHWAN'},
  {'emoji': '🐖', 'anlaut': 'S', 'wort': 'SCHWEIN'},
  {'emoji': '🦭', 'anlaut': 'S', 'wort': 'SEEHUND'},
  // T – 5 Einträge
  {'emoji': '🐯', 'anlaut': 'T', 'wort': 'TIGER'},
  {'emoji': '🐙', 'anlaut': 'T', 'wort': 'TINTENFISCH'},
  {'emoji': '🕊️', 'anlaut': 'T', 'wort': 'TAUBE'},
  {'emoji': '🍇', 'anlaut': 'T', 'wort': 'TRAUBEN'},
  {'emoji': '🥁', 'anlaut': 'T', 'wort': 'TROMMEL'},
  // V – 2 Einträge
  {'emoji': '🐦', 'anlaut': 'V', 'wort': 'VOGEL'},
  {'emoji': '🌋', 'anlaut': 'V', 'wort': 'VULKAN'},
  // W – 5 Einträge
  {'emoji': '🐺', 'anlaut': 'W', 'wort': 'WOLF'},
  {'emoji': '🌊', 'anlaut': 'W', 'wort': 'WELLE'},
  {'emoji': '🐳', 'anlaut': 'W', 'wort': 'WAL'},
  {'emoji': '🍉', 'anlaut': 'W', 'wort': 'WASSERMELONE'},
  {'emoji': '🪱', 'anlaut': 'W', 'wort': 'WURM'},
  // Z – 3 Einträge
  {'emoji': '🦓', 'anlaut': 'Z', 'wort': 'ZEBRA'},
  {'emoji': '🪥', 'anlaut': 'Z', 'wort': 'ZAHNBUERSTE'},
  {'emoji': '🎯', 'anlaut': 'Z', 'wort': 'ZIEL'},
];

/// Reimpaare: Wort → reimt auf
/// Alle Paare handgeprüft:
///   - echte Reimpaare (gleicher Endlaut, nicht nur ähnlich)
///   - alle Wörter Erstklässlern bekannt
///   - 'falsch'-Optionen reimen NICHT auf das Wort
const _reimPaare = [
  // -aus
  {
    'wort': 'Haus',
    'reimt': 'Maus',
    'falsch': ['Hund', 'Baum', 'Schuh'],
  },
  {
    'wort': 'Maus',
    'reimt': 'Haus',
    'falsch': ['Baum', 'Buch', 'Ball'],
  },
  {
    'wort': 'Klaus',
    'reimt': 'Maus',
    'falsch': ['Ring', 'Baum', 'Katze'],
  },
  // -all
  {
    'wort': 'Ball',
    'reimt': 'Stall',
    'falsch': ['Hund', 'Baum', 'Rose'],
  },
  {
    'wort': 'Stall',
    'reimt': 'Ball',
    'falsch': ['Hund', 'Rose', 'Mond'],
  },
  {
    'wort': 'Hall',
    'reimt': 'Ball',
    'falsch': ['Baum', 'Buch', 'Katze'],
  },
  // -ein
  {
    'wort': 'Bein',
    'reimt': 'Stein',
    'falsch': ['Ball', 'Tisch', 'Nase'],
  },
  {
    'wort': 'Stein',
    'reimt': 'Bein',
    'falsch': ['Baum', 'Buch', 'Ball'],
  },
  {
    'wort': 'Mein',
    'reimt': 'Bein',
    'falsch': ['Hund', 'Rose', 'Katze'],
  },
  // -isch
  {
    'wort': 'Fisch',
    'reimt': 'Tisch',
    'falsch': ['Hund', 'Baum', 'Ball'],
  },
  {
    'wort': 'Tisch',
    'reimt': 'Fisch',
    'falsch': ['Rose', 'Mond', 'Schuh'],
  },
  {
    'wort': 'Wisch',
    'reimt': 'Fisch',
    'falsch': ['Ball', 'Hund', 'Stern'],
  },
  // -und
  {
    'wort': 'Hund',
    'reimt': 'Mund',
    'falsch': ['Katze', 'Baum', 'Nase'],
  },
  {
    'wort': 'Mund',
    'reimt': 'Hund',
    'falsch': ['Ball', 'Rose', 'Mond'],
  },
  {
    'wort': 'Rund',
    'reimt': 'Hund',
    'falsch': ['Baum', 'Buch', 'Katze'],
  },
  // -aum
  {
    'wort': 'Baum',
    'reimt': 'Traum',
    'falsch': ['Hund', 'Rose', 'Buch'],
  },
  {
    'wort': 'Traum',
    'reimt': 'Baum',
    'falsch': ['Ball', 'Stern', 'Katze'],
  },
  {
    'wort': 'Raum',
    'reimt': 'Baum',
    'falsch': ['Hund', 'Buch', 'Rose'],
  },
  // -ind
  {
    'wort': 'Kind',
    'reimt': 'Wind',
    'falsch': ['Ball', 'Mond', 'Rose'],
  },
  {
    'wort': 'Wind',
    'reimt': 'Kind',
    'falsch': ['Hund', 'Baum', 'Schuh'],
  },
  // -uch
  {
    'wort': 'Buch',
    'reimt': 'Tuch',
    'falsch': ['Hund', 'Baum', 'Ball'],
  },
  {
    'wort': 'Tuch',
    'reimt': 'Buch',
    'falsch': ['Rose', 'Stern', 'Baum'],
  },
  {
    'wort': 'Kuchen',
    'reimt': 'Suchen',
    'falsch': ['Hund', 'Ball', 'Rose'],
  },
  // -acht
  {
    'wort': 'Nacht',
    'reimt': 'Acht',
    'falsch': ['Tag', 'Mond', 'Stern'],
  },
  {
    'wort': 'Acht',
    'reimt': 'Nacht',
    'falsch': ['Tag', 'Ball', 'Hund'],
  },
  {
    'wort': 'Macht',
    'reimt': 'Nacht',
    'falsch': ['Ball', 'Baum', 'Rose'],
  },
  // -ern
  {
    'wort': 'Stern',
    'reimt': 'Kern',
    'falsch': ['Mond', 'Sonne', 'Ball'],
  },
  {
    'wort': 'Kern',
    'reimt': 'Stern',
    'falsch': ['Hund', 'Ball', 'Rose'],
  },
  {
    'wort': 'Fern',
    'reimt': 'Stern',
    'falsch': ['Baum', 'Buch', 'Katze'],
  },
  // -atze
  {
    'wort': 'Katze',
    'reimt': 'Tatze',
    'falsch': ['Hund', 'Buch', 'Rose'],
  },
  {
    'wort': 'Tatze',
    'reimt': 'Katze',
    'falsch': ['Ball', 'Baum', 'Mond'],
  },
  {
    'wort': 'Matze',
    'reimt': 'Katze',
    'falsch': ['Hund', 'Rose', 'Schuh'],
  },
  // -ug
  {
    'wort': 'Zug',
    'reimt': 'Krug',
    'falsch': ['Ball', 'Mond', 'Rose'],
  },
  {
    'wort': 'Krug',
    'reimt': 'Zug',
    'falsch': ['Hund', 'Baum', 'Ball'],
  },
  {
    'wort': 'Bug',
    'reimt': 'Zug',
    'falsch': ['Rose', 'Stern', 'Katze'],
  },
  // -ot
  {
    'wort': 'Brot',
    'reimt': 'Rot',
    'falsch': ['Baum', 'Ball', 'Nase'],
  },
  {
    'wort': 'Rot',
    'reimt': 'Brot',
    'falsch': ['Blau', 'Gruen', 'Ball'],
  },
  {
    'wort': 'Boot',
    'reimt': 'Brot',
    'falsch': ['Hund', 'Rose', 'Ball'],
  },
  // -uh
  {
    'wort': 'Kuh',
    'reimt': 'Schuh',
    'falsch': ['Katze', 'Baum', 'Ball'],
  },
  {
    'wort': 'Schuh',
    'reimt': 'Kuh',
    'falsch': ['Hund', 'Rose', 'Baum'],
  },
  {
    'wort': 'Ruh',
    'reimt': 'Kuh',
    'falsch': ['Ball', 'Mond', 'Stern'],
  },
  // -eis
  {
    'wort': 'Eis',
    'reimt': 'Reis',
    'falsch': ['Ball', 'Hund', 'Mond'],
  },
  {
    'wort': 'Reis',
    'reimt': 'Eis',
    'falsch': ['Baum', 'Ball', 'Rose'],
  },
  {
    'wort': 'Weis',
    'reimt': 'Eis',
    'falsch': ['Hund', 'Katze', 'Stern'],
  },
  // -ang
  {
    'wort': 'Sang',
    'reimt': 'Gang',
    'falsch': ['Ball', 'Rose', 'Hund'],
  },
  {
    'wort': 'Gang',
    'reimt': 'Sang',
    'falsch': ['Baum', 'Ball', 'Mond'],
  },
  // -age
  {
    'wort': 'Tage',
    'reimt': 'Frage',
    'falsch': ['Hund', 'Baum', 'Ball'],
  },
  // -eise
  {
    'wort': 'Reise',
    'reimt': 'Weise',
    'falsch': ['Ball', 'Mond', 'Hund'],
  },
  // -ier
  {
    'wort': 'Tier',
    'reimt': 'Vier',
    'falsch': ['Ball', 'Baum', 'Rose'],
  },
  {
    'wort': 'Vier',
    'reimt': 'Tier',
    'falsch': ['Hund', 'Mond', 'Ball'],
  },
  // -ose
  {
    'wort': 'Rose',
    'reimt': 'Nase',
    'falsch': ['Ball', 'Hund', 'Baum'],
  },
  {
    'wort': 'Nase',
    'reimt': 'Rose',
    'falsch': ['Baum', 'Ball', 'Mond'],
  },
];

/// Wortpaare für Längenvergleich: {kurz, lang}
/// Beide Wörter Erstklässlern bekannt, deutlicher Längenunterschied.
const _wortPaare = [
  // 2 vs 7+
  {'kurz': 'Ei', 'lang': 'Elefant'},
  {'kurz': 'Ei', 'lang': 'Erdbeere'},
  {'kurz': 'Ei', 'lang': 'Eisbaer'},
  // 2-3 vs 6+
  {'kurz': 'Hut', 'lang': 'Hamster'},
  {'kurz': 'Hut', 'lang': 'Hubschrauber'},
  {'kurz': 'Bus', 'lang': 'Banane'},
  {'kurz': 'Kuh', 'lang': 'Krokodil'},
  {'kurz': 'Kuh', 'lang': 'Kirsche'},
  {'kurz': 'Arm', 'lang': 'Alligator'},
  {'kurz': 'Aas', 'lang': 'Apfelsaft'},
  {'kurz': 'See', 'lang': 'Seehund'},
  {'kurz': 'Eis', 'lang': 'Eiswuerfel'},
  {'kurz': 'Eis', 'lang': 'Eichhornchen'},
  {'kurz': 'Zug', 'lang': 'Zahnbuerste'},
  {'kurz': 'Hund', 'lang': 'Hamster'},
  {'kurz': 'Hund', 'lang': 'Hubschrauber'},
  {'kurz': 'Brot', 'lang': 'Banane'},
  {'kurz': 'Brot', 'lang': 'Bratwurst'},
  {'kurz': 'Wald', 'lang': 'Wasserfall'},
  {'kurz': 'Ball', 'lang': 'Ballon'},
  {'kurz': 'Ball', 'lang': 'Banane'},
  {'kurz': 'Baer', 'lang': 'Blaubeere'},
  {'kurz': 'Baer', 'lang': 'Brombeer'},
  {'kurz': 'Fisch', 'lang': 'Flamingo'},
  {'kurz': 'Fisch', 'lang': 'Frosch'},
  {'kurz': 'Gras', 'lang': 'Giraffe'},
  {'kurz': 'Hase', 'lang': 'Hamster'},
  {'kurz': 'Hase', 'lang': 'Hubschrauber'},
  {'kurz': 'Igel', 'lang': 'Indianer'},
  {'kurz': 'Katze', 'lang': 'Kaenguru'},
  {'kurz': 'Loewe', 'lang': 'Lokomotive'},
  {'kurz': 'Maus', 'lang': 'Murmeltier'},
  {'kurz': 'Maus', 'lang': 'Marienkaefer'},
  {'kurz': 'Nase', 'lang': 'Nashorn'},
  {'kurz': 'Pferd', 'lang': 'Pinguin'},
  {'kurz': 'Rose', 'lang': 'Rentier'},
  {'kurz': 'Rose', 'lang': 'Regenbogen'},
  {'kurz': 'Schuh', 'lang': 'Schlange'},
  {'kurz': 'Schuh', 'lang': 'Schildkroete'},
  {'kurz': 'Stern', 'lang': 'Stieglitz'},
  {'kurz': 'Tier', 'lang': 'Tintenfisch'},
  {'kurz': 'Vogel', 'lang': 'Vulkan'},
  {'kurz': 'Wolf', 'lang': 'Wassermelone'},
  {'kurz': 'Zebra', 'lang': 'Zahnbuerste'},
];

/// Alle Großbuchstaben (ohne Umlaute für Klasse 1–2)
const _letters = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

// ── Feedback-Texte ────────────────────────────────────────────────────────────

const _feedbacksCorrect = [
  '🌟 Super gemacht!',
  '🎉 Richtig!',
  '🏆 Toll!',
  '✨ Klasse!',
  '🎊 Wunderbar!',
  '🥳 Genau richtig!',
  '💪 Stark!',
];


// ── Engine ────────────────────────────────────────────────────────────────────

class LetterTaskEngine {
  final int grade;
  final int level;
  final Random _rng;

  LetterTaskEngine({required this.grade, required this.level, int? seed})
    : _rng = Random(seed);

  int get _diffStage {
    if (level <= 3) return 1;
    if (level <= 7) return 2;
    if (level <= 12) return 3;
    if (level <= 20) return 4;
    return 5;
  }

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Generiert genau 5 Aufgaben – je eine pro Slot, zufällig gemischt.
  List<LetterTask> generate(int count) {
    final List<LetterTaskType> slots;
    switch (_diffStage) {
      case 1:
        slots = [
          LetterTaskType.anlaut,
          LetterTaskType.grossKlein,
          LetterTaskType.bildWort,
          LetterTaskType.buchstabeMalen,
          LetterTaskType.reihenfolge,
        ];
        break;
      case 2:
        slots = [
          LetterTaskType.anlaut,
          LetterTaskType.grossKlein,
          LetterTaskType.bildWort,
          LetterTaskType.buchstabeMalen,
          LetterTaskType.reim,
        ];
        break;
      default: // Stufe 3–5
        slots = [
          LetterTaskType.anlaut,
          LetterTaskType.grossKlein,
          LetterTaskType.bildWort,
          LetterTaskType.buchstabeMalen,
          LetterTaskType.wortlaenge,
        ];
    }

    final usedSlots = List<LetterTaskType>.from(slots.take(count))
      ..shuffle(_rng);

    // Damit dieselbe Emoji-Quelle nicht doppelt gezogen wird
    final usedEmojis = <String>{};

    final tasks = <LetterTask>[];
    for (final type in usedSlots) {
      final task = _generate(type, usedEmojis);
      if (task != null) {
        tasks.add(task);
        if (task.emoji != null) usedEmojis.add(task.emoji!);
      }
    }
    return tasks;
  }

  // ── Generatoren ───────────────────────────────────────────────────────────

  LetterTask? _generate(LetterTaskType type, Set<String> usedEmojis) {
    switch (type) {
      case LetterTaskType.anlaut:
        return _genAnlaut(usedEmojis);
      case LetterTaskType.grossKlein:
        return _genGrossKlein();
      case LetterTaskType.bildWort:
        return _genBildWort(usedEmojis);
      case LetterTaskType.buchstabeMalen:
        return _genBuchstabeMalen();
      case LetterTaskType.reihenfolge:
        return _genReihenfolge();
      case LetterTaskType.reim:
        return _genReim();
      case LetterTaskType.wortlaenge:
        return _genWortlaenge();
    }
  }

  // ── Anlaut ────────────────────────────────────────────────────────────────

  LetterTask _genAnlaut(Set<String> usedEmojis) {
    final pool = _emojiData
        .where((e) => !usedEmojis.contains(e['emoji']))
        .toList();
    final item = pool[_rng.nextInt(pool.length)];
    final correct = item['anlaut']!;
    final emoji = item['emoji']!;

    // 3 falsche Buchstaben die sich nicht zu sehr ähneln
    final wrongPool = _letters.where((l) => l != correct).toList()
      ..shuffle(_rng);
    final wrongs = wrongPool.take(3).toList();
    final opts = [correct, ...wrongs]..shuffle(_rng);

    return LetterTask(
      type: LetterTaskType.anlaut,
      questionText: 'Mit welchem Buchstaben beginnt das?',
      emoji: emoji,
      options: opts,
      correctAnswer: correct,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Sprich das Wort laut!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Groß → Klein ─────────────────────────────────────────────────────────

  LetterTask _genGrossKlein() {
    final letter = _letters[_rng.nextInt(_letters.length)];
    final correct = letter.toLowerCase();

    final wrongPool =
        _letters.where((l) => l != letter).map((l) => l.toLowerCase()).toList()
          ..shuffle(_rng);
    final opts = [correct, ...wrongPool.take(3)]..shuffle(_rng);

    return LetterTask(
      type: LetterTaskType.grossKlein,
      questionText: 'Welcher Kleinbuchstabe gehört zu $letter?',
      emoji: letter, // Großbuchstabe als "Bild"
      options: opts,
      correctAnswer: correct,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Groß und Klein sind ein Paar!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Bild → Wort mit Lücke ─────────────────────────────────────────────────

  LetterTask _genBildWort(Set<String> usedEmojis) {
    // Nur Wörter die kurz genug sind (max 7 Buchstaben)
    final pool = _emojiData
        .where(
          (e) => !usedEmojis.contains(e['emoji']) && e['wort']!.length <= 7,
        )
        .toList();

    if (pool.isEmpty) {
      // Fallback auf alle
      return _genAnlaut(usedEmojis);
    }

    final item = pool[_rng.nextInt(pool.length)];
    final emoji = item['emoji']!;
    final word = item['wort']!;

    // Lücke: zufälligen Vokal bevorzugen (damit lösbar), sonst random
    final vowelIndices = <int>[];
    for (int i = 0; i < word.length; i++) {
      if ('AEIOU'.contains(word[i])) vowelIndices.add(i);
    }
    final missingIdx = vowelIndices.isNotEmpty
        ? vowelIndices[_rng.nextInt(vowelIndices.length)]
        : _rng.nextInt(word.length);

    final correct = word[missingIdx];

    // Wort mit Lücke als Display-Text: K_TZE
    final displayWord = word.characters
        .toList()
        .asMap()
        .entries
        .map((e) => e.key == missingIdx ? '_' : e.value)
        .join();

    final wrongPool = _letters.where((l) => l != correct).toList()
      ..shuffle(_rng);
    final opts = [correct, ...wrongPool.take(3)]..shuffle(_rng);

    return LetterTask(
      type: LetterTaskType.bildWort,
      questionText: 'Welcher Buchstabe fehlt in $displayWord?',
      emoji: emoji,
      options: opts,
      correctAnswer: correct,
      fullWord: word,
      missingIndex: missingIdx,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Sprich das Wort langsam!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Buchstabe Malen ───────────────────────────────────────────────────────

  LetterTask _genBuchstabeMalen() {
    // Stufe 1–2: nur einfache Buchstaben (keine Problembuchstaben für Anfänger)
    final easyLetters = _diffStage <= 2
        ? ['A', 'E', 'I', 'O', 'U', 'M', 'S', 'T', 'L', 'N', 'R', 'K']
        : _letters;

    final letter = easyLetters[_rng.nextInt(easyLetters.length)];

    return LetterTask(
      type: LetterTaskType.buchstabeMalen,
      questionText: 'Male den Buchstaben $letter!',
      options: [], // kein Multiple Choice – wird gemalt
      correctAnswer: letter,
      letterToDraw: letter,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Versuch es nochmal!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Reihenfolge: A B __ D ─────────────────────────────────────────────────

  LetterTask _genReihenfolge() {
    // Startpunkt so wählen dass 4 aufeinanderfolgende Buchstaben passen
    final maxStart = _letters.length - 4;
    final startIdx = _rng.nextInt(maxStart);
    final seq = _letters.sublist(startIdx, startIdx + 4);

    // Lücke zufällig: Index 0, 1, 2 oder 3
    // Stufe 1: nur Mitte (Index 1 oder 2) – einfacher
    // Stufe 2+: auch Anfang (0) und Ende (3) möglich
    final int blankIdx;
    if (_diffStage <= 1) {
      blankIdx = _rng.nextBool() ? 1 : 2;
    } else {
      blankIdx = _rng.nextInt(4);
    }

    final correct = seq[blankIdx];

    final display = seq
        .asMap()
        .entries
        .map((e) => e.key == blankIdx ? '__' : e.value)
        .toList();

    // Distraktoren: nahe Buchstaben im Alphabet sind schwieriger
    final correctIdx = _letters.indexOf(correct);
    final nearPool = <String>[];
    for (int delta = 1; nearPool.length < 4 && delta < 10; delta++) {
      final before = correctIdx - delta;
      final after = correctIdx + delta;
      if (before >= 0 && !seq.contains(_letters[before])) {
        nearPool.add(_letters[before]);
      }
      if (after < _letters.length && !seq.contains(_letters[after])) {
        nearPool.add(_letters[after]);
      }
    }
    nearPool.shuffle(_rng);
    final opts = [correct, ...nearPool.take(3)]..shuffle(_rng);

    return LetterTask(
      type: LetterTaskType.reihenfolge,
      questionText: '${display.join('  ')} – welcher Buchstabe fehlt?',
      options: opts,
      correctAnswer: correct,
      letterSequence: seq,
      blankIndex: blankIdx,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Das ABC hilft dir!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Reim ─────────────────────────────────────────────────────────────────

  LetterTask _genReim() {
    final pair = _reimPaare[_rng.nextInt(_reimPaare.length)];
    final correct = pair['reimt'] as String;
    final wrongs = List<String>.from(pair['falsch'] as List)..shuffle(_rng);
    final opts = [correct, ...wrongs.take(3)]..shuffle(_rng);

    return LetterTask(
      type: LetterTaskType.reim,
      questionText: 'Was reimt sich auf „${pair['wort']}"?',
      options: opts,
      correctAnswer: correct,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Was klingt gleich?',
      difficultyLevel: _diffStage,
    );
  }

  // ── Wortlänge ─────────────────────────────────────────────────────────────

  LetterTask _genWortlaenge() {
    final pair = _wortPaare[_rng.nextInt(_wortPaare.length)];
    final shorter = pair['kurz']!;
    final longer = pair['lang']!;

    // Zufällig: längeres oder kürzeres gesucht
    final askLonger = _rng.nextBool();
    final correct = askLonger ? longer : shorter;
    final wrong = askLonger ? shorter : longer;

    // 2-Option-Frage (nur diese beiden Wörter)
    final opts = [correct, wrong]..shuffle(_rng);

    return LetterTask(
      type: LetterTaskType.wortlaenge,
      questionText: askLonger
          ? 'Welches Wort ist länger?'
          : 'Welches Wort ist kürzer?',
      options: opts,
      correctAnswer: correct,
      wordA: shorter,
      wordB: longer,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Zähl die Buchstaben!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Helfer ────────────────────────────────────────────────────────────────

  String _pickRandom(List<String> list) => list[_rng.nextInt(list.length)];

  // ── Statische UI-Helfer ───────────────────────────────────────────────────

  static String stageName(int stage) {
    switch (stage) {
      case 1:
        return 'Starter';
      case 2:
        return 'Einsteiger';
      case 3:
        return 'Fortgeschritten';
      case 4:
        return 'Profi';
      default:
        return 'Meister';
    }
  }

  static String stageEmoji(int stage) {
    switch (stage) {
      case 1:
        return '🌱';
      case 2:
        return '🌿';
      case 3:
        return '🌳';
      case 4:
        return '⚡';
      default:
        return '🔥';
    }
  }
}
