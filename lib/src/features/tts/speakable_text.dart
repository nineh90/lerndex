// ============================================================================
// SPRECHBARER TEXT
//
// Lexis Antworten enthalten Markdown, LaTeX-Formeln ($...$) und Emojis. Die
// Sprachausgabe würde das Zeichen für Zeichen vorlesen („Stern Stern“,
// „Backslash frac“). Hier wird daraus ein Text, der sich normal anhört.
// ============================================================================

final _emojiPattern = RegExp(
  r'[\u{1F300}-\u{1FAFF}]|[\u{2600}-\u{27BF}]|[\u{FE00}-\u{FE0F}]|'
  r'[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{2700}-\u{27BF}]|'
  r'[\u{E000}-\u{F8FF}]|[\u{200D}]|[\u{20E3}]|[\u{FE0F}]|'
  r'[\u{D83C}-\u{DBFF}][\u{DC00}-\u{DFFF}]|[\u{2B50}]|[\u{2B05}-\u{2B07}]|'
  r'[\u{2934}-\u{2935}]|[\u{3030}]|[\u{303D}]|[\u{25A0}-\u{25FF}]|'
  r'[\u{2300}-\u{23FF}]',
  unicode: true,
);

/// Entfernt Emojis. "🌟 Ja, 3 Äpfel!" → "Ja, 3 Äpfel!"
String stripEmojis(String text) => text
    .replaceAll(_emojiPattern, '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

/// Macht eine Tutor-Antwort vorlesbar: Formeln in Worte, Markdown und
/// Emojis raus.
String speakableText(String text) {
  var s = text;

  // Versteckte Steuer-Tags wie [FACH:Mathe] oder [KORREKT:ja], falls noch drin
  s = s.replaceAll(RegExp(r'\[[A-ZÄÖÜ]+:[^\]]*\]'), '');

  // Formeln ($$...$$ und $...$) in Worte übersetzen
  s = s.replaceAllMapped(
    RegExp(r'\$\$(.+?)\$\$', dotAll: true),
    (m) => ' ${_speakMath(m[1]!)} ',
  );
  s = s.replaceAllMapped(RegExp(r'\$(.+?)\$'), (m) => _speakMath(m[1]!));

  // Markdown
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (m) => m[1]!,
  ); // [Text](url) → Text
  s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\*\*|__|`'), '');
  s = s.replaceAllMapped(
    RegExp(r'(^|[\s(])[*_]([^*_\n]+)[*_](?=[\s.,!?:;)]|$)', multiLine: true),
    (m) => '${m[1]}${m[2]}',
  );

  s = stripEmojis(s);

  // Zeilenumbrüche als Pause, damit Aufzählungen nicht zusammenlaufen
  s = s.replaceAllMapped(RegExp(r'([^.!?:;,\s])\s*\n+\s*'), (m) => '${m[1]}. ');
  s = s.replaceAll(RegExp(r'\s*\n+\s*'), ' ');

  return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

/// Übersetzt eine LaTeX-Formel in gesprochenes Deutsch.
String _speakMath(String latex) {
  var s = latex;

  // Verschachtelte Befehle von innen nach außen auflösen
  String? previous;
  while (previous != s) {
    previous = s;
    s = s.replaceAllMapped(
      RegExp(r'\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}'),
      (m) => ' ${m[1]} geteilt durch ${m[2]} ',
    );
    s = s.replaceAllMapped(
      RegExp(r'\\sqrt\s*\{([^{}]*)\}'),
      (m) => ' Wurzel aus ${m[1]} ',
    );
    s = s.replaceAllMapped(
      RegExp(r'\\text(?:bf|it|rm)?\s*\{([^{}]*)\}'),
      (m) => m[1]!,
    );
  }

  s = s.replaceAllMapped(RegExp(r'\^\{?2\}?'), (_) => ' hoch zwei ');
  s = s.replaceAllMapped(RegExp(r'\^\{?3\}?'), (_) => ' hoch drei ');
  s = s.replaceAllMapped(
    RegExp(r'\^\{([^{}]*)\}|\^(\S)'),
    (m) => ' hoch ${m[1] ?? m[2]} ',
  );

  const words = {
    r'\cdot': ' mal ',
    r'\times': ' mal ',
    r'\div': ' geteilt durch ',
    r'\pm': ' plus minus ',
    r'\leq': ' kleiner oder gleich ',
    r'\le': ' kleiner oder gleich ',
    r'\geq': ' größer oder gleich ',
    r'\ge': ' größer oder gleich ',
    r'\neq': ' ungleich ',
    r'\ne': ' ungleich ',
    r'\approx': ' ungefähr ',
    r'\pi': ' Pi ',
    r'\%': ' Prozent ',
    r'\infty': ' unendlich ',
  };
  // Längere Befehle zuerst, damit \leq nicht als \le + q gelesen wird
  final keys = words.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    s = s.replaceAll(k, words[k]!);
  }

  s = s
      .replaceAll('=', ' gleich ')
      .replaceAll('+', ' plus ')
      .replaceAll('<', ' kleiner als ')
      .replaceAll('>', ' größer als ')
      .replaceAll('*', ' mal ')
      .replaceAll('·', ' mal ')
      .replaceAll(':', ' geteilt durch ')
      .replaceAll('/', ' geteilt durch ');
  // Minus nur als Rechenzeichen, nicht als Bindestrich in Wörtern
  s = s.replaceAllMapped(
    RegExp(r'(^|[\s\d)])-(?=\s*[\d(a-zA-Z])'),
    (m) => '${m[1]} minus ',
  );

  // Restliche Befehle und Klammern weg
  s = s.replaceAll(RegExp(r'\\[a-zA-Z]+'), ' ');
  s = s.replaceAll(RegExp(r'[{}\\]'), ' ');

  return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}
