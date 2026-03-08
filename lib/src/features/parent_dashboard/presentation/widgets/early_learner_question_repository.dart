import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';

// ============================================================================
// EARLY LEARNER QUESTION GENERATOR v2
//
// Generiert KI-Aufgaben für Klasse 1–2 im _EarlyQuestion-kompatiblen Format.
// Fragen werden in Firestore gecacht (analog zu AiQuestionCacheRepository).
//
// v2 Änderungen:
// • Strikte Fach-Trennung: VERBOTEN-Listen in jedem Prompt
// • Grade-Differenzierung: Klasse 1 (bis 10) vs Klasse 2 (bis 20)
// • Validierung: Unbeantwortbare Fragen werden rausgefiltert
// • Vergleichsfragen brauchen immer ZWEI Zahlen im questionEmoji
//
// Cache-Pfad:
//   users/{uid}/children/{childId}/early_question_cache/{subject}/questions/{id}
//
// Fragetypen die generiert werden:
//   - imageChoice: Emoji-Bild + 4 Emoji-Antworten
//   - anlaut: Welcher Buchstabe beginnt das Wort?
//   - counting: Wie viele siehst du?
//   - pattern: Was kommt als nächstes?
//   - oddOneOut: Was passt nicht dazu?
// ============================================================================

/// Darstellung einer KI-generierten Early-Learner-Frage (JSON-sicher).
class EarlyAiQuestion {
  final String type; // 'imageChoice'|'anlaut'|'counting'|'pattern'|'oddOneOut'
  final String questionEmoji;
  final String questionText;
  final List<String> options;
  final String correctAnswer;
  final String feedbackCorrect;
  final String feedbackWrong;
  final List<String>? orderedAnswers; // nur für sizeOrder
  final String subject;
  final bool played;
  final DateTime createdAt;
  final String? docId; // Firestore-Dokument-ID (wird nicht serialisiert)

  EarlyAiQuestion({
    required this.type,
    required this.questionEmoji,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    required this.feedbackCorrect,
    required this.feedbackWrong,
    this.orderedAnswers,
    required this.subject,
    this.played = false,
    DateTime? createdAt,
    this.docId,
  }) : createdAt = createdAt ?? DateTime.now();

  EarlyAiQuestion copyWithDocId(String id) => EarlyAiQuestion(
    type: type,
    questionEmoji: questionEmoji,
    questionText: questionText,
    options: options,
    correctAnswer: correctAnswer,
    feedbackCorrect: feedbackCorrect,
    feedbackWrong: feedbackWrong,
    orderedAnswers: orderedAnswers,
    subject: subject,
    played: played,
    createdAt: createdAt,
    docId: id,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'questionEmoji': questionEmoji,
    'questionText': questionText,
    'options': options,
    'correctAnswer': correctAnswer,
    'feedbackCorrect': feedbackCorrect,
    'feedbackWrong': feedbackWrong,
    if (orderedAnswers != null) 'orderedAnswers': orderedAnswers,
    'subject': subject,
    'played': played,
    'createdAt': createdAt.toIso8601String(),
  };

  factory EarlyAiQuestion.fromJson(Map<String, dynamic> json) =>
      EarlyAiQuestion(
        type: json['type'] as String? ?? 'imageChoice',
        questionEmoji: json['questionEmoji'] as String? ?? '❓',
        questionText: json['questionText'] as String? ?? '',
        options: List<String>.from(json['options'] as List? ?? []),
        correctAnswer: json['correctAnswer'] as String? ?? '',
        feedbackCorrect: json['feedbackCorrect'] as String? ?? '🌟 Super!',
        feedbackWrong: json['feedbackWrong'] as String? ?? '💪 Nochmal!',
        orderedAnswers: json['orderedAnswers'] != null
            ? List<String>.from(json['orderedAnswers'] as List)
            : null,
        subject: json['subject'] as String? ?? '',
        played: json['played'] as bool? ?? false,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

// ── Repository ─────────────────────────────────────────────────────────────────

class EarlyLearnerQuestionRepository {
  final FirebaseFirestore _firestore;
  GenerativeModel? _model;
  bool _initialized = false;

  static const int _refillThreshold = 5;
  static const int _batchSize = 10;

  EarlyLearnerQuestionRepository(this._firestore);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _model = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(
        temperature: 0.8,
        maxOutputTokens: 4096,
        topP: 0.95,
        responseMimeType: 'application/json',
      ),
    );
    _initialized = true;
  }

  // ── Cache-Pfad ────────────────────────────────────────────────────────────

  CollectionReference _cacheRef(
    String userId,
    String childId,
    String subject,
  ) => _firestore
      .collection('users')
      .doc(userId)
      .collection('children')
      .doc(childId)
      .collection('early_question_cache')
      .doc(subject)
      .collection('questions');

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Liefert [count] ungespielte Fragen. Generiert wenn nötig.
  ///
  /// Wenn count > verfügbare Fragen im Cache:
  /// → Synchron nachgenerieren bis genug da sind (max 2 Durchläufe)
  /// → Das ermöglicht dem Quiz-Screen mehr Fragen anzufordern als
  ///   ein einzelner Batch liefert (z.B. 15 anfordern, Filter wirft
  ///   einige raus, aber es bleiben genug für 5 gute Fragen übrig)
  Future<List<EarlyAiQuestion>> getQuestions({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int count = 5,
  }) async {
    try {
      await _ensureInitialized();
      var unplayed = await _loadUnplayed(userId, childId, subject);

      // Wenn nicht genug Fragen da sind: synchron nachgenerieren
      // Max 2 Generierungs-Durchläufe um nicht ewig zu blockieren
      int attempts = 0;
      while (unplayed.length < count && attempts < 2) {
        attempts++;
        print(
          '🔄 EarlyLearner: Nur ${unplayed.length}/$count Fragen für $subject '
          '→ generiere nach (Versuch $attempts)...',
        );
        await _generateAndCache(
          userId: userId,
          childId: childId,
          child: child,
          subject: subject,
        );
        unplayed = await _loadUnplayed(userId, childId, subject);
      }

      // Hintergrund-Refill starten wenn Vorrat nach Entnahme knapp wird
      if (unplayed.length - count < _refillThreshold) {
        _generateAndCache(
          userId: userId,
          childId: childId,
          child: child,
          subject: subject,
        );
      }

      if (unplayed.isEmpty) {
        print('⚠️ EarlyLearner: Cache leer trotz Generierung → leere Liste');
        return [];
      }

      final selected = unplayed.take(count).toList();
      // WICHTIG: Erst markieren, DANN zurückgeben – sonst werden dieselben
      // Fragen beim schnellen Neu-Start nochmal ausgespielt (Race condition)
      await _markPlayedByIds(userId, childId, subject, selected);
      return selected;
    } catch (e) {
      print('⚠️ EarlyQuestionRepo.getQuestions Fehler: $e');
      return [];
    }
  }

  /// Füllt den Cache wenn leer (Pre-Fetch bei Kind-Erstellung).
  Future<void> prefillIfEmpty({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
  }) async {
    try {
      final unplayed = await _loadUnplayed(userId, childId, subject);
      if (unplayed.length >= _refillThreshold) return;
      await _generateAndCache(
        userId: userId,
        childId: childId,
        child: child,
        subject: subject,
      );
    } catch (e) {
      print('⚠️ EarlyQuestionRepo.prefill Fehler: $e');
    }
  }

  /// Füllt den Cache bis MINDESTENS [targetCount] Fragen vorhanden sind.
  /// Wird vom Splash-Screen aufgerufen damit genug Fragen für den
  /// Client-seitigen Fach-Filter übrig bleiben.
  ///
  /// Beispiel: targetCount=20, batchSize=10 → generiert bis zu 2 Batches
  Future<void> prefillForQuiz({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int targetCount = 20,
  }) async {
    try {
      await _ensureInitialized();
      var unplayed = await _loadUnplayed(userId, childId, subject);

      int attempts = 0;
      while (unplayed.length < targetCount && attempts < 3) {
        attempts++;
        print(
          '🧒 EarlyPrefill: ${unplayed.length}/$targetCount für $subject '
          '→ generiere Batch $attempts...',
        );
        await _generateAndCache(
          userId: userId,
          childId: childId,
          child: child,
          subject: subject,
        );
        unplayed = await _loadUnplayed(userId, childId, subject);
      }

      print(
        '✅ EarlyPrefill: $subject hat jetzt ${unplayed.length} Fragen im Cache',
      );
    } catch (e) {
      print('⚠️ EarlyQuestionRepo.prefillForQuiz Fehler: $e');
    }
  }

  // ── Intern ────────────────────────────────────────────────────────────────

  Future<List<EarlyAiQuestion>> _loadUnplayed(
    String userId,
    String childId,
    String subject,
  ) async {
    try {
      final snap = await _cacheRef(
        userId,
        childId,
        subject,
      ).where('played', isEqualTo: false).get();
      final list = snap.docs.map((d) {
        final q = EarlyAiQuestion.fromJson(d.data() as Map<String, dynamic>);
        return q.copyWithDocId(d.id);
      }).toList();
      // Shufflen damit nicht immer dieselben Fragen zuerst kommen
      list.shuffle();
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Markiert Fragen anhand ihrer Firestore-Doc-ID als gespielt.
  /// Schneller und zuverlässiger als Suche nach questionText.
  Future<void> _markPlayedByIds(
    String userId,
    String childId,
    String subject,
    List<EarlyAiQuestion> questions,
  ) async {
    try {
      final ref = _cacheRef(userId, childId, subject);
      final batch = _firestore.batch();
      for (final q in questions) {
        if (q.docId != null) {
          batch.update(ref.doc(q.docId), {'played': true});
        }
      }
      await batch.commit();
    } catch (e) {
      print('⚠️ _markPlayedByIds Fehler: $e');
    }
  }

  // Alte Methode bleibt für Kompatibilität (wird nicht mehr aktiv genutzt)
  Future<void> _markPlayed(
    String userId,
    String childId,
    String subject,
    List<EarlyAiQuestion> questions,
  ) async {
    final ref = _cacheRef(userId, childId, subject);
    final batch = _firestore.batch();
    for (final q in questions) {
      // Suche nach dem Dokument mit gleichem questionText
      final docs = await ref
          .where('questionText', isEqualTo: q.questionText)
          .limit(1)
          .get();
      for (final d in docs.docs) {
        batch.update(d.reference, {'played': true});
      }
    }
    await batch.commit();
  }

  Future<List<EarlyAiQuestion>> _generateAndCache({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
  }) async {
    await _ensureInitialized();
    print('🤖 EarlyLearner: Generiere $_batchSize Fragen für $subject...');

    final prompt = _buildPrompt(subject: subject, child: child);

    try {
      final response = await _model!
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 30));

      final text = response.text ?? '';
      final parsed = _parseQuestions(text, subject);

      // ── NEU: Fach-Filter VOR dem Cachen anwenden ──────────────────
      // Nur Fragen die zum Fach passen werden in Firestore geschrieben.
      // So ist der Cache immer sauber und das Quiz kann sich darauf
      // verlassen dass jede Frage aus dem Cache auch passt.
      final questions = parsed.where((q) => _passesSubjectFilter(q)).toList();

      final filtered = parsed.length - questions.length;
      if (filtered > 0) {
        print(
          '🔍 EarlyLearner: $filtered/${parsed.length} Fragen für $subject '
          'vom Fach-Filter entfernt (vor dem Cachen)',
        );
      }

      if (questions.isNotEmpty) {
        await _writeToCache(userId, childId, subject, questions);
        print(
          '✅ EarlyLearner: ${questions.length} Fragen für $subject gecacht',
        );
      }

      return questions;
    } catch (e) {
      print('❌ EarlyLearner: Generierung fehlgeschlagen für $subject: $e');
      return [];
    }
  }

  Future<void> _writeToCache(
    String userId,
    String childId,
    String subject,
    List<EarlyAiQuestion> questions,
  ) async {
    final ref = _cacheRef(userId, childId, subject);
    final batch = _firestore.batch();
    for (final q in questions) {
      final doc = ref.doc();
      batch.set(doc, q.toJson());
    }
    await batch.commit();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FACH-FILTER – wird VOR dem Cachen angewendet
  //
  // Gleiche Logik wie _filterBySubject im Quiz-Screen, aber arbeitet
  // direkt auf EarlyAiQuestion (String-basiertes type-Feld).
  // So kommen nur saubere, fachkonforme Fragen in den Firestore-Cache.
  // ══════════════════════════════════════════════════════════════════════════

  bool _optionsAreNumbers(List<String> opts) =>
      opts.every((o) => RegExp(r'^\d+$').hasMatch(o));

  bool _optionsAreLetters(List<String> opts) =>
      opts.every((o) => o.length == 1 && RegExp(r'[A-ZÄÖÜa-zäöü]').hasMatch(o));

  bool _emojiHasNumbers(String emoji) =>
      RegExp(r'[0-9]|[1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣0️⃣]').hasMatch(emoji);

  /// Prüft ob eine generierte Frage zum deklarierten Fach passt.
  bool _passesSubjectFilter(EarlyAiQuestion q) {
    final text = q.questionText.toLowerCase();
    final type = q.type;
    final subject = q.subject;

    switch (subject) {
      case 'Mathe':
        switch (type) {
          case 'counting':
            return _optionsAreNumbers(q.options);
          case 'imageChoice':
            return _optionsAreNumbers(q.options) ||
                text.contains('zahl') ||
                text.contains('größer') ||
                text.contains('kleiner') ||
                text.contains('wie viele') ||
                text.contains('mehr') ||
                text.contains('weniger') ||
                text.contains('rechne') ||
                text.contains('plus') ||
                text.contains('+') ||
                text.contains('minus') ||
                text.contains('ergebnis');
          case 'pattern':
            return _optionsAreNumbers(q.options) ||
                _emojiHasNumbers(q.questionEmoji);
          case 'sizeOrder':
            return _optionsAreNumbers(q.options);
          default:
            return false; // anlaut, oddOneOut → nicht für Mathe
        }

      case 'Deutsch':
        switch (type) {
          case 'anlaut':
            return _optionsAreLetters(q.options);
          case 'pattern':
            return _optionsAreLetters(q.options);
          case 'oddOneOut':
            return !text.contains('wie viele') &&
                !text.contains('zähl') &&
                !text.contains('zahl') &&
                !text.contains('farbe') &&
                !text.contains('form') &&
                !text.contains('rund') &&
                !text.contains('eckig') &&
                (text.contains('fängt') ||
                    text.contains('beginnt') ||
                    text.contains('buchstab') ||
                    text.contains('nicht mit'));
          default:
            return false; // counting, imageChoice → nicht für Deutsch
        }

      case 'FarbenFormen':
        switch (type) {
          case 'imageChoice':
            return text.contains('farbe') ||
                text.contains('form') ||
                text.contains('rot') ||
                text.contains('blau') ||
                text.contains('gelb') ||
                text.contains('grün') ||
                text.contains('rund') ||
                text.contains('eckig') ||
                text.contains('kreis') ||
                text.contains('dreieck') ||
                text.contains('quadrat') ||
                text.contains('gleiche');
          case 'pattern':
            return !_optionsAreNumbers(q.options) &&
                !_optionsAreLetters(q.options);
          case 'oddOneOut':
            return (text.contains('nicht') ||
                    text.contains('farb') ||
                    text.contains('form') ||
                    text.contains('rund') ||
                    text.contains('rot') ||
                    text.contains('blau')) &&
                !text.contains('buchstab') &&
                !text.contains('zahl');
          case 'sizeOrder':
            return !_optionsAreNumbers(q.options);
          default:
            return false;
        }

      default:
        return true;
    }
  }

  // ── Prompt ────────────────────────────────────────────────────────────────

  /// Gibt den maximalen Zahlenbereich passend zur Klassenstufe zurück.
  int _maxNumber(ChildModel child) => child.grade <= 1 ? 10 : 20;

  String _buildPrompt({required String subject, required ChildModel child}) {
    final subjectInstructions = _subjectInstructions(subject, child);
    final maxNum = _maxNumber(child);
    final gradeInfo = child.grade <= 1
        ? 'Klasse 1 (${child.age} Jahre) – NUR Zahlen von 1 bis $maxNum!'
        : 'Klasse 2 (${child.age} Jahre) – Zahlen von 1 bis $maxNum, einfaches Plus und Minus.';

    return '''
Du bist ein Lernspiel-Designer für Kinder in $gradeInfo
Erstelle GENAU $_batchSize spielerische Aufgaben für das Fach "$subject".

WICHTIG: Die Kinder können noch NICHT lesen. Alles muss durch Emojis kommuniziert werden!
WICHTIG: Alle Zahlen in Aufgaben und Antworten DÜRFEN NICHT größer als $maxNum sein!

$subjectInstructions

Antworte NUR mit einem JSON-Array ohne Markdown-Backticks, kein Text davor oder danach:
[
  {
    "type": "counting",
    "questionEmoji": "🍎🍎🍎🍎",
    "questionText": "Wie viele Äpfel siehst du?",
    "options": ["2", "3", "4", "5"],
    "correctAnswer": "4",
    "feedbackCorrect": "🌟 Genau, 4 Äpfel!",
    "feedbackWrong": "💪 Zähl nochmal!"
  }
]

Erlaubte Typen:
- "counting": Emojis zählen (questionEmoji hat die gezählten Emojis, options = Zahlen als Text "1","2","3"...)
- "imageChoice": Welches Bild passt? (questionEmoji = Hinweis-Emoji, options = 4 Emojis)
- "anlaut": Welcher Buchstabe beginnt das Wort? (questionEmoji = Emoji des Wortes, options = 4 Buchstaben als Großbuchstaben)
- "pattern": Was kommt als nächstes? (questionEmoji zeigt das Muster MIT ❓ am Ende z.B. "🔴🔵🔴🔵❓", options = 4 mögliche Fortsetzungen, correctAnswer = das Element das als nächstes im Muster kommt)
- "oddOneOut": Was passt nicht dazu? (questionEmoji = 4 Emojis davon 1 nicht passend, options = dieselben 4 Emojis, correctAnswer = das EINE Emoji das nicht passt)

WICHTIG FÜR PATTERN: 
- Das Muster ENDET mit ❓
- correctAnswer ist immer das Element das dem Muster nach als nächstes kommen würde
- Beispiel: questionEmoji "🔴🔵🔴🔵❓" → correctAnswer "🔴" (weil nach 🔵 kommt 🔴)
- Beispiel: questionEmoji "🟩🔴🟩🔴🟩❓" → correctAnswer "🔴" (weil nach 🟩 kommt 🔴)

REGELN:
- IMMER GENAU 4 options – niemals 2 oder 3, immer exakt 4!
- correctAnswer muss EXAKT eine der options sein (Zeichenfolge identisch!)
- feedbackCorrect, feedbackWrong und questionText IMMER AUF DEUTSCH – keine Ausnahme!
- feedbackCorrect nennt die richtige Antwort: "🌟 Richtig, das ist K wie Katze!"
- feedbackWrong gibt einen ermutigenden Hinweis: "💪 Fast! K-K-Katze!"
- Altersgerecht für ${child.age} Jahre
- NUR deutsche Satzstruktur für alle Texte
- Kontrolliere jede Frage: options.length MUSS 4 sein, sonst füge Distraktoren hinzu
- KEINE Zahl in options oder correctAnswer darf größer als $maxNum sein!

WICHTIG FÜR VERGLEICHSFRAGEN:
- Bei "Welche Zahl ist größer/kleiner?" MÜSSEN IMMER ZWEI Zahlen in questionEmoji stehen!
  RICHTIG: questionEmoji "3️⃣ und 7️⃣", questionText "Welche Zahl ist größer?"
  FALSCH:  questionEmoji "❓", questionText "Welche Zahl ist größer?" ← UNBEANTWORTBAR!
- Bei Vergleichsfragen: correctAnswer muss die größere/kleinere der ZWEI genannten Zahlen sein
- Die 4 options enthalten die correctAnswer + 3 andere Zahlen als Distraktoren
''';
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FACH-SPEZIFISCHE INSTRUKTIONEN – mit VERBOTEN-Listen
  // ════════════════════════════════════════════════════════════════════════════

  String _subjectInstructions(String subject, ChildModel child) {
    final maxNum = _maxNumber(child);
    final gradeSpecific = child.grade <= 1
        ? 'Klasse 1: NUR Zahlen 1–$maxNum, nur Zählen und einfaches "Welche Zahl ist größer?". KEIN Plus/Minus.'
        : 'Klasse 2: Zahlen 1–$maxNum, Zählen, einfaches Plus und Minus (Ergebnis max $maxNum), Zahlenvergleiche.';

    switch (subject) {
      case 'Mathe':
        return '''
THEMEN für Mathe ($gradeSpecific):
- Zählen (Objekt-Emojis zählen, MAXIMAL $maxNum Objekte!)
- Zahlenvergleiche: "3️⃣ und 7️⃣ – Welche Zahl ist größer?" (IMMER zwei Zahlen zeigen!)
${child.grade >= 2 ? '- Einfaches Rechnen: "3 + 2 = ?" oder "5 - 1 = ?" (Ergebnis max $maxNum!)' : ''}
- Zahlen-Muster: 1️⃣2️⃣1️⃣2️⃣❓ oder 1️⃣2️⃣3️⃣❓ (nur Zahlen bis $maxNum!)
Verwende viele Tier- und Obst-Emojis zum ZÄHLEN.

NUR diese Typen für Mathe: "counting", "imageChoice", "pattern"
- counting: Emojis zählen → options MÜSSEN Zahlen als Text sein ("1","2","3","4")
  MAXIMAL $maxNum Emojis zum Zählen!
  Beispiel: questionEmoji "🐟🐟🐟", questionText "Wie viele Fische siehst du?", options ["2","3","4","5"], correctAnswer "3"
- imageChoice: Rechenaufgaben und Zahlenvergleiche → options MÜSSEN Zahlen als Text sein
  Bei Vergleichen: questionEmoji MUSS ZWEI Zahlen enthalten!
  Beispiel: questionEmoji "3️⃣ und 7️⃣", questionText "Welche Zahl ist größer?", options ["3","7","5","2"], correctAnswer "7"
  Beispiel: questionEmoji "🍎🍎 ➕ 🍎", questionText "2 + 1 = ?", options ["2","3","4","1"], correctAnswer "3"
- pattern: NUR Zahlen-Muster! questionEmoji MUSS Zahlen-Emojis (1️⃣2️⃣ etc.) enthalten!
  Beispiel: questionEmoji "1️⃣2️⃣3️⃣4️⃣❓", options ["5","3","6","4"], correctAnswer "5"
  
Mischung: 4 "counting", 3 "imageChoice", 3 "pattern"

🚫 STRENG VERBOTEN bei Mathe:
- KEINE Buchstaben-Aufgaben (kein Anlaut, kein ABC)
- KEINE Farben-Aufgaben (kein "Welche Farbe?", keine Farb-Emojis 🔴🔵 als Muster)
- KEINE Formen-Aufgaben (kein Kreis, Dreieck, Quadrat)
- KEINE Obst-Muster als Pattern (z.B. 🍎🍌🍎🍌❓ ist VERBOTEN – das ist kein Mathe!)
- KEINE Farb-Muster als Pattern (z.B. 🔴🔵🔴🔵❓ ist VERBOTEN – gehört zu FarbenFormen!)
- KEINE Tier-Muster als Pattern (z.B. 🐶🐱🐶🐱❓ ist VERBOTEN!)
- KEIN "anlaut", KEIN "oddOneOut" Typ bei Mathe!
- Alle options MÜSSEN Zahlen als Text sein – KEINE Emojis, KEINE Buchstaben, KEINE Wörter
- KEINE Zahl größer als $maxNum!
- KEINE Vergleichsfragen ohne zwei konkrete Zahlen im questionEmoji!
''';

      case 'Deutsch':
        return '''
THEMEN für Deutsch Klasse 1–2:
- Anlaute: Womit beginnt 🐱 (Katze)? → K
- Anfangsbuchstaben erkennen (Emojis bekannter deutscher Wörter)
- Buchstaben-Muster: A-B-A-B-A-❓ (options = Buchstaben)
- Odd one out NACH ANFANGSBUCHSTABEN: 
  "Was fängt NICHT mit B an?" → 🐻🍌🐝🎸 → Gitarre fängt mit G an!
  WICHTIG: oddOneOut muss IMMER nach Anfangsbuchstaben fragen!

⚠️ EMOJI-REGEL: Verwende NUR Emojis deren deutscher Name EINDEUTIG und BEKANNT ist!
Erlaubte Emojis (mit ihren deutschen Namen):
  🐱=Katze 🐶=Hund 🐟=Fisch 🐦=Vogel 🐻=Bär 🐝=Biene 🐸=Frosch 🐭=Maus
  🐘=Elefant 🐴=Pferd 🐷=Schwein 🐰=Hase 🦁=Löwe 🐍=Schlange 🐢=Schildkröte
  🍎=Apfel 🍌=Banane 🍓=Erdbeere 🌞=Sonne 🌙=Mond ⭐=Stern 🌳=Baum
  🏠=Haus 🚗=Auto 🎸=Gitarre ⚽=Ball 📖=Buch 🔑=Schlüssel 👃=Nase
  👀=Auge 🦶=Fuß 🖐️=Hand ✏️=Stift 🪑=Stuhl 🚌=Bus 🌸=Blume
  🍪=Keks 🧀=Käse 🥕=Karotte 🍕=Pizza 🎂=Torte 🍦=Eis
  🎈=Ballon 🎁=Geschenk 🪟=Fenster 🚪=Tür 🛏️=Bett 🧦=Socke

VERBOTENE Emojis (mehrdeutige Namen):
  🍬 (Bonbon? Süßigkeit? Candy?) ❌
  🥧 (Kuchen? Pie? Torte?) ❌
  🏀 (Basketball? Ball?) ❌
  Jedes Emoji das NICHT in der erlaubten Liste steht!

NUR diese Typen für Deutsch: "anlaut", "pattern", "oddOneOut"
- anlaut: options = 4 verschiedene GROSSBUCHSTABEN (A-Z)
  Beispiel: questionEmoji "🐱", questionText "Womit fängt KATZE an?", options ["K","M","A","T"], correctAnswer "K"
  feedbackCorrect: "🌟 Super! K wie Katze!"
  feedbackWrong: "💪 Hör mal: K-K-Katze!"
- pattern: options = 4 verschiedene GROSSBUCHSTABEN (A-Z)
  Beispiel: questionEmoji "A B A B A ❓", options ["A","B","C","D"], correctAnswer "B"
- oddOneOut: 4 Emojis, 3 fangen mit DEMSELBEN Buchstaben an, 1 mit einem ANDEREN
  questionText MUSS den Buchstaben nennen: "Was fängt NICHT mit B an?"
  PRÜFE VOR DER AUSGABE: Stimmen die Anfangsbuchstaben wirklich? 
    🐻=Bär(B) ✓  🍌=Banane(B) ✓  🐝=Biene(B) ✓  🎸=Gitarre(G) ✓ → correctAnswer 🎸 ✓
  Beispiel: questionEmoji "🐻🍌🐝🎸", questionText "Was fängt NICHT mit B an?", 
  options ["🐻","🍌","🐝","🎸"], correctAnswer "🎸"
  feedbackCorrect: "🎉 Gitarre fängt mit G an, nicht mit B!"
  feedbackWrong: "💪 Bär, Banane, Biene – alle mit B! Aber Gitarre?"

Mischung: 5 "anlaut", 3 "pattern", 2 "oddOneOut"

🚫 STRENG VERBOTEN bei Deutsch:
- KEINE Zahlen-Aufgaben (kein Zählen, kein Rechnen, keine Zahlenvergleiche)
- KEINE Farben-Aufgaben (kein "Welche Farbe?", keine Farbzuordnung)
- KEINE Formen-Aufgaben (kein Kreis, Dreieck, Quadrat)
- KEINE allgemeinen "Was passt nicht dazu?" ohne Buchstaben-Bezug!
  (z.B. "🐱🐶🐰🚗 – Was ist kein Tier?" ist VERBOTEN – hat nichts mit Buchstaben zu tun!)
- KEIN "counting", KEIN "imageChoice" Typ bei Deutsch!
- Alle options bei anlaut und pattern MÜSSEN einzelne Großbuchstaben sein
- Bei oddOneOut: Frage MUSS IMMER einen konkreten Buchstaben nennen ("Was fängt NICHT mit X an?")
- KEINE Emojis verwenden die NICHT in der erlaubten Liste stehen!
''';

      case 'FarbenFormen':
        return '''
THEMEN für Farben & Formen Klasse 1–2:
- Grundfarben benennen: Rot, Blau, Gelb, Grün, Orange, Lila
- Grundformen benennen: Kreis, Quadrat, Dreieck, Rechteck, Stern
- Farbzuordnung: "Was ist auch rot?" → 🔴 mit roten Objekten
- Formzuordnung: "Was ist auch rund?" → ⭕ mit runden Objekten
- Farb-Muster: 🔴🔵🔴🔵❓
- Formen-Muster: ⭕🔺⭕🔺❓  
- Odd one out nach FARBE: "Was ist NICHT rot?" (3 rote + 1 anderes)
- Odd one out nach FORM: "Was ist NICHT rund?" (3 runde + 1 eckiges)

NUR diese Typen für FarbenFormen: "imageChoice", "pattern", "oddOneOut"
- imageChoice: Farben oder Formen erkennen
  Beispiel 1: questionEmoji "🔴", questionText "Welche Farbe siehst du?", options ["Rot","Blau","Gelb","Grün"], correctAnswer "Rot"
  Beispiel 2: questionEmoji "⭕", questionText "Was ist auch rund?", options ["🌕","📦","🔺","⬛"], correctAnswer "🌕"
  Beispiel 3: questionEmoji "🟡", questionText "Was hat diese Farbe?", options ["🍓","🍋","🍀","🫐"], correctAnswer "🍋"
- pattern: NUR Farb- oder Form-Emojis als Muster!
  Beispiel: questionEmoji "🔴🔵🔴🔵❓", options ["🔴","🔵","🟡","🟢"], correctAnswer "🔴"
- oddOneOut: Bezug MUSS eine Farbe oder Form sein!
  Beispiel: questionEmoji "🔴🍓🌹🔵", questionText "Was ist NICHT rot?", options ["🔴","🍓","🌹","🔵"], correctAnswer "🔵"

Mischung: 4 "imageChoice", 3 "pattern", 3 "oddOneOut"

🚫 STRENG VERBOTEN bei FarbenFormen:
- KEINE Zahlen-Aufgaben (kein Zählen! "Wie viele?" ist VERBOTEN!)
- KEINE Buchstaben-Aufgaben (kein Anlaut, kein ABC, keine Buchstaben als Antwort)
- KEINE Tier/Obst-Muster ohne Farbbezug (z.B. 🐶🐱🐶🐱❓ ist VERBOTEN)
- KEINE allgemeinen "Was passt nicht dazu?" ohne Farb/Form-Bezug
  (z.B. "Was ist kein Tier?" ist VERBOTEN)
- KEIN "counting", KEIN "anlaut" Typ bei FarbenFormen!
- Bei oddOneOut: Frage MUSS IMMER eine Farbe oder Form nennen ("Was ist NICHT rot?", "Was ist NICHT rund?")
''';

      default:
        return 'Erstelle altersgerechte Aufgaben mit Emojis für Klasse 1–2.';
    }
  }

  // ── Parser ────────────────────────────────────────────────────────────────

  List<EarlyAiQuestion> _parseQuestions(String text, String subject) {
    final questions = <EarlyAiQuestion>[];

    try {
      String cleaned = text.trim();
      // Entferne Markdown-Backticks falls vorhanden
      cleaned = cleaned.replaceAll('```json', '').replaceAll('```', '').trim();

      final startArr = cleaned.indexOf('[');
      final endArr = cleaned.lastIndexOf(']');
      if (startArr == -1 || endArr == -1 || endArr <= startArr) {
        print('⚠️ EarlyParser: Kein JSON-Array gefunden');
        return [];
      }

      final jsonStr = cleaned.substring(startArr, endArr + 1);
      final List<dynamic> jsonList = jsonDecode(jsonStr);

      for (final item in jsonList) {
        if (item is! Map<String, dynamic>) continue;
        final q = _parseQuestion(item, subject);
        if (q != null) questions.add(q);
      }
    } catch (e) {
      print('❌ EarlyParser: JSON-Fehler: $e');
      print('   Text-Anfang: ${text.substring(0, text.length.clamp(0, 200))}');
    }

    print('✅ EarlyParser: ${questions.length} valide Fragen geparst');
    return questions;
  }

  EarlyAiQuestion? _parseQuestion(Map<String, dynamic> json, String subject) {
    try {
      final type = json['type']?.toString() ?? 'imageChoice';

      // questionEmoji kann ein JSON-Array-String sein z.B. '["🍎", "🍌", "🍓", "🚗"]'
      // → normalisieren zu "🍎 🍌 🍓 🚗"
      String questionEmoji = json['questionEmoji']?.toString() ?? '';
      if (questionEmoji.startsWith('[')) {
        try {
          final decoded = jsonDecode(questionEmoji);
          if (decoded is List) {
            questionEmoji = decoded.join(' ');
          }
        } catch (_) {
          // Wenn JSON-Parse fehlschlägt: eckige Klammern und Kommas entfernen
          questionEmoji = questionEmoji
              .replaceAll('[', '')
              .replaceAll(']', '')
              .replaceAll('"', '')
              .replaceAll(',', '')
              .trim();
        }
      }
      final questionText = json['questionText']?.toString() ?? '';
      if (questionText.isEmpty || questionEmoji.isEmpty) return null;

      final rawOptions = json['options'];
      if (rawOptions == null || rawOptions is! List || rawOptions.length < 2) {
        return null;
      }
      var options = List<String>.from(rawOptions);

      final correctAnswer = json['correctAnswer']?.toString() ?? '';
      if (correctAnswer.isEmpty) return null;

      // Sicherstellen dass correctAnswer in options enthalten ist
      if (!options.contains(correctAnswer)) {
        options.insert(0, correctAnswer);
      }

      // IMMER genau 4 options – Distraktoren auffüllen wenn nötig
      const _fillerNumbers = ['1', '2', '3', '4', '5', '6', '7', '8'];
      const _fillerLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
      const _fillerEmojis = ['🌟', '🎈', '🌈', '🦄', '🍀', '🌙'];
      while (options.length < 4) {
        // Passenden Distraktor wählen basierend auf vorhandenen Optionen
        final isNumber = options.every((o) => RegExp(r'^\d+$').hasMatch(o));
        final isLetter = options.every(
          (o) => o.length == 1 && RegExp(r'[A-Za-z]').hasMatch(o),
        );
        final pool = isNumber
            ? _fillerNumbers
            : isLetter
            ? _fillerLetters
            : _fillerEmojis;
        final candidate = pool.firstWhere(
          (f) => !options.contains(f),
          orElse: () => '❓',
        );
        options.add(candidate);
      }
      // Auf max 4 kürzen (falls KI mehr geliefert hat)
      if (options.length > 4) {
        // correctAnswer behalten
        final idx = options.indexOf(correctAnswer);
        if (idx > 3) {
          options.removeAt(idx);
          options.insert(0, correctAnswer);
        }
        options = options.take(4).toList();
      }
      // Mischen damit correctAnswer nicht immer an Position 0 ist
      options.shuffle();

      final question = EarlyAiQuestion(
        type: type,
        questionEmoji: questionEmoji,
        questionText: questionText,
        options: options,
        correctAnswer: correctAnswer,
        feedbackCorrect: json['feedbackCorrect']?.toString() ?? '🌟 Richtig!',
        feedbackWrong: json['feedbackWrong']?.toString() ?? '💪 Nochmal!',
        orderedAnswers: json['orderedAnswers'] != null
            ? List<String>.from(json['orderedAnswers'] as List)
            : null,
        subject: subject,
      );

      // ── VALIDIERUNG: Unbeantwortbare Fragen rausfiltern ─────────────
      if (!_isValidQuestion(question)) {
        print(
          '⚠️ EarlyParser: Frage rausgefiltert (Validierung): ${question.questionText}',
        );
        return null;
      }

      return question;
    } catch (e) {
      print('⚠️ EarlyParser: Frage-Parse-Fehler: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VALIDIERUNG – Prüft ob eine Frage tatsächlich beantwortbar ist
  // ══════════════════════════════════════════════════════════════════════════

  bool _isValidQuestion(EarlyAiQuestion q) {
    final text = q.questionText.toLowerCase();

    // 1. correctAnswer muss in options enthalten sein
    if (!q.options.contains(q.correctAnswer)) {
      print('   → correctAnswer "${q.correctAnswer}" nicht in options');
      return false;
    }

    // 2. Vergleichsfragen ("größer"/"kleiner") müssen zwei Zahlen referenzieren
    if (text.contains('größer') ||
        text.contains('kleiner') ||
        text.contains('mehr') ||
        text.contains('weniger')) {
      // questionEmoji oder questionText muss mindestens zwei Zahlen enthalten
      final allText = '${q.questionEmoji} ${q.questionText}';
      final numberMatches = RegExp(r'\d+').allMatches(allText).toList();
      // Auch Zahlen-Emojis zählen
      final emojiNumbers = RegExp(r'[0-9]️⃣').allMatches(allText).toList();
      final totalNumbers = numberMatches.length + emojiNumbers.length;

      if (totalNumbers < 2) {
        print(
          '   → Vergleichsfrage ohne zwei Zahlen: "${q.questionText}" emoji="${q.questionEmoji}"',
        );
        return false;
      }
    }

    // 3. Mathe: Alle Options müssen Zahlen sein (wenn subject Mathe)
    if (q.subject == 'Mathe') {
      final allNumbers = q.options.every((o) => RegExp(r'^\d+$').hasMatch(o));
      if (!allNumbers && q.type != 'pattern') {
        // Bei pattern können auch Zahlen-Emojis als options vorkommen
        print('   → Mathe-Frage mit Nicht-Zahlen-Options: ${q.options}');
        return false;
      }
    }

    // 4. Deutsch anlaut: Options müssen einzelne Buchstaben sein
    if (q.subject == 'Deutsch' && q.type == 'anlaut') {
      final allLetters = q.options.every(
        (o) => o.length == 1 && RegExp(r'[A-ZÄÖÜa-zäöü]').hasMatch(o),
      );
      if (!allLetters) {
        print('   → Anlaut-Frage mit Nicht-Buchstaben-Options: ${q.options}');
        return false;
      }
    }

    // 5. Keine leeren oder zu kurzen Fragen
    if (q.questionText.length < 5) {
      print('   → Frage zu kurz: "${q.questionText}"');
      return false;
    }

    // 6. Mindestens 4 verschiedene Options (keine Duplikate)
    if (q.options.toSet().length < 3) {
      print('   → Zu viele doppelte Options: ${q.options}');
      return false;
    }

    return true;
  }
}

// ── Riverpod Provider ─────────────────────────────────────────────────────────

final earlyLearnerQuestionRepoProvider =
    Provider<EarlyLearnerQuestionRepository>((ref) {
      return EarlyLearnerQuestionRepository(FirebaseFirestore.instance);
    });
