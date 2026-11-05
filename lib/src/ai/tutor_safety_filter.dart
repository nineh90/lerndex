// Lokale Sicherheitsprüfung für Kindernachrichten an Lexi (vor jedem
// KI-Aufruf). Ohne Firebase, damit sie einzeln testbar ist
// (test/ai/tutor_safety_filter_test.dart).
//
// Drei Ergebnisse:
// - help:    Das Kind deutet an, dass es sich etwas antun will, dass ihm
//            jemand wehtut oder dass es gemobbt wird. Lexi antwortet warm und
//            nennt Ansprechpartner (helpResponse), statt abzuweisen.
// - blocked: Gewalt, Waffen, Drogen, Sex ohne erkennbare Notlage. Lexi lehnt
//            ab, nennt aber trotzdem die Nummer gegen Kummer (falls doch eine
//            Notlage dahintersteckt, die die Muster nicht erkennen).
// - ok:      geht an die KI. Ob es ein Schulthema ist, entscheidet dort der
//            Systemprompt (kein Stichwortfilter mehr: „Kreis“ enthält „reise“,
//            „Pizza“ gehört zur Bruchrechnung).
//
// Der eigentliche Schutz für alles andere liegt bei den Safety-Settings von
// Vertex AI und dem Systemprompt.

enum TutorSafety { ok, help, blocked }

class TutorSafetyFilter {
  TutorSafetyFilter._();

  /// Antwort auf Hilferufe. Bewusst nicht „sprich mit deinen Eltern“: Es
  /// können auch die Eltern sein, die dem Kind wehtun.
  static const helpResponse =
      'Danke, dass du mir das erzählst. 💜 Das klingt nach etwas, das dich '
      'gerade sehr belastet. Ich bin nur eine Lern-App und kann dir dabei nicht '
      'richtig helfen, aber ein Mensch kann es: Bitte erzähl es einem '
      'Erwachsenen, dem du vertraust, zum Beispiel jemandem aus deiner Familie, '
      'einer Lehrerin oder einem Lehrer. Du kannst auch kostenlos und anonym '
      'die „Nummer gegen Kummer“ anrufen: 116 111. Wenn du gerade in Gefahr '
      'bist, ruf die 110 an.';

  static const blockedResponse =
      'Darüber kann ich leider nicht mit dir sprechen. Ich bin Lexi und helfe '
      'dir beim Lernen! 📚 Falls dich etwas bedrückt oder dir jemand wehtut: '
      'Erzähl es einem Erwachsenen, dem du vertraust, oder ruf kostenlos die '
      '„Nummer gegen Kummer“ an: 116 111.';

  // Ein Wort (mit Umlauten; \w kennt in Dart keine Umlaute).
  static const _w = r'[a-zäöüß]+';
  // Bis zu n Wörter dazwischen: „mich (heute) (wieder) schlagen“
  static String _gap(int n) => '(?:$_w\\s+){0,$n}';

  static final List<RegExp> _helpPatterns = [
    // Suizid, Selbstverletzung
    RegExp(r'selbstmord|suizid|selbstverletz|selbst\s+verletz'),
    RegExp(r'nicht\s+mehr\s+(?:leben|da\s+sein|aufwachen)'),
    RegExp(r'keinen\s+sinn\s+mehr'),
    RegExp(
      '(?:will|möchte|wünsch$_w|wäre|wär)\\s+${_gap(3)}(?:sterben|tot)(?![a-zäöüß])',
    ),
    RegExp(r'(?<![a-zäöüß])tot\s+sein'),
    // „ritzen“ nur auf das Kind bezogen („Diamant ritzt Glas“ ist Chemie)
    RegExp('(?<![a-zäöüß])ich\\s+${_gap(2)}ritze(?:n)?(?![a-zäöüß])'),
    RegExp('ritz$_w\\s+mich'),
    RegExp('mich\\s+${_gap(3)}(?:ge)?ritzt'),
    RegExp('bring(?:e|st|t|en)?\\s+mich\\s+${_gap(2)}um(?![a-zäöüß])'),
    RegExp(
      'mich\\s+${_gap(2)}(?:töten|umbringen|ritzen|verletzen|erhängen|vergiften)',
    ),
    RegExp(
      'mir\\s+${_gap(2)}(?:weh\\s*tun|wehtun|was\\s+antun|etwas\\s+antun)',
    ),
    // Wunsch, jemanden zu töten: auch das ist ein Fall für Erwachsene
    RegExp('(?:will|möchte|werde)\\s+${_gap(3)}(?:töten|umbringen|ermorden)'),
    // Gewalt oder Übergriffe gegen das Kind
    RegExp(
      '(?:schlägt|schlug|haut|tritt|trat|verprügelt|prügelt|quält|bedroht|'
      'erpresst|missbraucht|vergewaltigt|begrapscht|befummelt|würgt|'
      'schubst|kneift|beißt)\\s+${_gap(2)}(?:mich|mir)(?![a-zäöüß])',
    ),
    RegExp(
      '(?<![a-zäöüß])(?:mich|mir)\\s+${_gap(3)}(?:schlagen|geschlagen|hauen|'
      'gehauen|treten|getreten|verprügeln|verprügelt|anfassen|angefasst|'
      'missbrauch$_w|missbraucht|bedroh$_w|erpress$_w|töten|umbringen|'
      'würgen|gewürgt|einsperren|eingesperrt)',
    ),
    RegExp(
      '(?:werde|wurde|werd)\\s+${_gap(3)}(?:geschlagen|verprügelt|gemobbt|'
      'missbraucht|bedroht|erpresst|angefasst|eingesperrt|gewürgt|getreten)',
    ),
    RegExp(r'mobb(?:t|en)\s+mich|gemobbt'),
    RegExp('angst\\s+vor\\s+(?:mein$_w|papa|mama|zu\\s+hause|daheim)'),
  ];

  /// Schulbegriffe, die ein gesperrtes Wort enthalten. Sie werden entfernt,
  /// bevor die Sperrliste greift.
  static final List<RegExp> _schoolTerms = [
    RegExp(r'gewalten?teilung|gewaltmonopol|gewaltfrei\w*|gewaltlos\w*'),
    RegExp(r'waffenstillstand\w*'),
    RegExp(r'blut(?:kreislauf|gefäß|körperchen|druck|plasma|zelle|gruppe)\w*'),
    RegExp(r'(?:nach|vor|auf|an|zu|durch|über|um|ein|ab|zurück)schlagen'),
    RegExp(r'schlagzeile|schlagwort|taktschlag|herzschlag|schlagzeug'),
    RegExp(r'abtöten'),
    RegExp(r'(?:sexuelle|ungeschlechtliche|geschlechtliche)\s+fortpflanzung'),
    RegExp(r'sexualkunde|sexualerziehung'),
    RegExp(r'drogen(?:prävention|aufklärung|beratung)'),
  ];

  static final List<RegExp> _blockedPatterns = [
    RegExp(r'gewalt'),
    RegExp(r'waffe'),
    RegExp(r'(?<![a-zäöüß])sex'),
    RegExp(r'drogen'),
    RegExp(r'schlagen'),
    RegExp(r'töten'),
    RegExp(r'(?<![a-zäöüß])blut(?![a-zäöüß])|blutig'),
  ];

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Text ohne die erlaubten Schulbegriffe (für Sperrliste und Eltern-Flag).
  static String stripSchoolTerms(String text) {
    var lower = _normalize(text);
    for (final pattern in _schoolTerms) {
      lower = lower.replaceAll(pattern, ' ');
    }
    return lower;
  }

  static bool needsHelp(String text) {
    final lower = _normalize(text);
    return _helpPatterns.any((p) => p.hasMatch(lower));
  }

  static bool isBlocked(String text) {
    final lower = stripSchoolTerms(text);
    return _blockedPatterns.any((p) => p.hasMatch(lower));
  }

  static TutorSafety check(String text) {
    if (needsHelp(text)) return TutorSafety.help;
    if (isBlocked(text)) return TutorSafety.blocked;
    return TutorSafety.ok;
  }
}
