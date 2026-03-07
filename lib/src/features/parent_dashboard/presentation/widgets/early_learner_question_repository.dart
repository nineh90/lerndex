import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';

// ============================================================================
// EARLY LEARNER QUESTION GENERATOR
//
// Generiert KI-Aufgaben für Klasse 1–2 im _EarlyQuestion-kompatiblen Format.
// Fragen werden in Firestore gecacht (analog zu AiQuestionCacheRepository).
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
  Future<List<EarlyAiQuestion>> getQuestions({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int count = 5,
  }) async {
    try {
      await _ensureInitialized();
      final unplayed = await _loadUnplayed(userId, childId, subject);

      // Hintergrund-Refill wenn Vorrat knapp
      if (unplayed.length < _refillThreshold) {
        _generateAndCache(
          userId: userId,
          childId: childId,
          child: child,
          subject: subject,
        );
      }

      if (unplayed.isEmpty) {
        // Synchron generieren als Fallback
        final fresh = await _generateAndCache(
          userId: userId,
          childId: childId,
          child: child,
          subject: subject,
        );
        return fresh.take(count).toList();
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
      final questions = _parseQuestions(text, subject);

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

  // ── Prompt ────────────────────────────────────────────────────────────────

  String _buildPrompt({required String subject, required ChildModel child}) {
    final subjectInstructions = _subjectInstructions(subject);

    return '''
Du bist ein Lernspiel-Designer für Kinder in Klasse 1–2 (${child.age} Jahre).
Erstelle GENAU $_batchSize spielerische Aufgaben für das Fach "$subject".

WICHTIG: Die Kinder können noch NICHT lesen. Alles muss durch Emojis kommuniziert werden!

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
- "counting": Emojis zählen (questionEmoji hat die gezählten Emojis, options = Zahlen)
- "imageChoice": Welches Bild passt? (questionEmoji = Suchbegriff, options = 4 Emojis)
- "anlaut": Welcher Buchstabe beginnt das Wort? (questionEmoji = Emoji des Wortes, options = 4 Buchstaben)
- "pattern": Was kommt als nächstes? (questionEmoji zeigt das Muster mit ❓, options = 4 Emojis oder Buchstaben)
- "oddOneOut": Was passt nicht dazu? (questionEmoji = 4 Emojis davon 1 falsch, options = die 4 Emojis, correctAnswer = das nicht passende)

REGELN:
- Mische alle Typen: je 2 "counting", 2 "anlaut", 2 "imageChoice", 2 "pattern", 2 "oddOneOut"
- IMMER GENAU 4 options – niemals 2 oder 3, immer exakt 4!
- correctAnswer muss EXAKT eine der options sein
- feedbackCorrect, feedbackWrong und questionText IMMER AUF DEUTSCH – keine Ausnahme!
- feedbackCorrect nennt die richtige Antwort: "🌟 Richtig, das ist K wie Katze!"
- feedbackWrong gibt einen kleinen Hinweis: "💪 K-K-Katze!"
- Altersgerecht für 6–8 Jahre
- NUR deutsche Satzstruktur für alle Texte, auch beim Fach Englisch
- Kontrolliere jede Frage: options.length MUSS 4 sein, sonst füge Distraktoren hinzu
''';
  }

  String _subjectInstructions(String subject) {
    switch (subject) {
      case 'Mathe':
        return '''
THEMEN für Mathe Klasse 1–2:
- Zählen bis 20 (Objekt-Emojis zählen)
- Grundrechenarten einfach (Emojis dazuzählen/wegnehmen)
- Größenvergleiche (größer/kleiner mit Tier-Emojis)
- Muster erkennen (Farbe-Emoji-Folgen: 🔴🔵🔴?)
- Zahlen vergleichen: Welche Zahl ist größer?
Verwende viele Tier- und Obst-Emojis zum Zählen.
''';

      case 'Deutsch':
        return '''
THEMEN für Deutsch Klasse 1–2:
- Anlaute: Womit beginnt 🐱 (Katze)? → K
- Vokale/Konsonanten erkennen
- Einfache Wortbilder: Welches Bild passt zum Wortanfang?
- Reimwörter: Was reimt sich auf "Maus"? (🏠 Haus, 🐸 Frosch, 🌊 Meer, 🌸 Blume) → 🏠
- Silben-Muster (A-B-A-B bei Buchstaben)
- Odd one out: Welches Tier beginnt NICHT mit B?
Nutze nur gut erkennbare Emojis für bekannte Wörter.
''';

      case 'FarbenFormen':
        return '''
THEMEN für Farben & Formen Klasse 1–2:
- Grundfarben erkennen: Rot, Blau, Gelb, Grün, Orange, Lila
- Grundformen erkennen: Kreis, Quadrat, Dreieck, Rechteck
- Was hat diese Farbe? (Welches Objekt ist rot/blau/gelb?)
- Was hat diese Form? (Was ist rund/eckig/dreieckig?)
- Farb-Muster: 🔴🔵🔴🔵❓
- Odd one out nach Farbe: Was ist nicht rot?
- Odd one out nach Form: Was ist nicht rund?
- Größenvergleiche mit Formen

WICHTIG: Alle questionText und Texte AUF DEUTSCH. Keine englischen Wörter.
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

      return EarlyAiQuestion(
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
    } catch (e) {
      print('⚠️ EarlyParser: Frage-Parse-Fehler: $e');
      return null;
    }
  }
}

// ── Riverpod Provider ─────────────────────────────────────────────────────────

final earlyLearnerQuestionRepoProvider =
    Provider<EarlyLearnerQuestionRepository>((ref) {
      return EarlyLearnerQuestionRepository(FirebaseFirestore.instance);
    });
