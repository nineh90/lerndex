import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:confetti/confetti.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/learning_time/learning_time_tracker.dart';
import 'package:lerndex/src/features/parent_dashboard/presentation/widgets/early_learner_question_repository.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/avatar_progress_bar.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/treasure_chest_overlay.dart';

// ============================================================================
// EARLY LEARNER QUIZ SCREEN – Klasse 1–2 (v2)
//
// Neu in v2:
// • TTS: Frage wird automatisch vorgelesen (wenn TTS aktiv)
// • TTS: Feedback wird gesprochen ("Richtig toll gemacht!")
// • TTS: Ergebnis am Ende wird vorgelesen
// • Konfetti-Effekt bei richtiger Antwort (confetti Package)
// • Differenziertes Haptic Feedback (light/heavy/selection)
// • Avatar-Fortschrittsanzeige statt einfacher Dots
// • Lautsprecher-Button zum erneuten Vorlesen
// • Shake-Animation bei falscher Antwort
//
// Aufgabentypen:
// 1. BILD-AUSWAHL     → Emoji-Bild + 4 große Emoji-Buttons
// 2. ANLAUT-AUFGABE   → Bild → welcher Anfangsbuchstabe?
// 3. ZAHLEN-AUFGABE   → Wie viele siehst du?
// 4. WORT-ZU-BILD     → Welches Bild passt zum Wort?
// 5. PATTERN          → Was kommt als nächstes? (Muster erkennen)
// 6. ODD ONE OUT      → Was passt nicht dazu?
// 7. SIZE ORDER       → Tippe vom Kleinsten zum Größten!
// ============================================================================

// ── Fragetypen ────────────────────────────────────────────────────────────────

enum _QuestionType {
  imageChoice, // Bild + 4 Bild-Antworten
  anlaut, // Welcher Buchstabe beginnt das Wort?
  counting, // Wie viele sind es?
  wordToImage, // Welches Bild passt zum Wort?
  pattern, // Was kommt als nächstes? (Muster erkennen)
  oddOneOut, // Was passt nicht dazu?
  sizeOrder, // Tippe in der richtigen Reihenfolge (klein → groß)
}

class _EarlyQuestion {
  final _QuestionType type;
  final String questionEmoji; // Großes Bild/Emoji als Frage
  final String questionText; // Wird vorgelesen / als Hinweis gezeigt
  final List<String>
  options; // Immer 3-4 Optionen (Emojis, Buchstaben oder Zahlen)
  final String correctAnswer;
  final String feedbackCorrect;
  final String feedbackWrong;

  /// Nur für sizeOrder: Die korrekte Reihenfolge der Optionen.
  /// Bei anderen Typen: null (wird ignoriert).
  final List<String>? orderedAnswers;

  const _EarlyQuestion({
    required this.type,
    required this.questionEmoji,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    this.feedbackCorrect = '🌟 Super!',
    this.feedbackWrong = '💪 Nochmal!',
    this.orderedAnswers,
  });
}

// ── Fragendatenbank nach Fach ─────────────────────────────────────────────────

final Map<String, List<_EarlyQuestion>> _questionBank = {
  'Mathe': [
    const _EarlyQuestion(
      type: _QuestionType.counting,
      questionEmoji: '🍎🍎🍎',
      questionText: 'Wie viele Äpfel siehst du?',
      options: ['1', '2', '3', '4'],
      correctAnswer: '3',
      feedbackCorrect: '🌟 Ja, 3 Äpfel!',
      feedbackWrong: '💪 Zähl nochmal!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.counting,
      questionEmoji: '⭐⭐',
      questionText: 'Wie viele Sterne siehst du?',
      options: ['1', '2', '3', '4'],
      correctAnswer: '2',
      feedbackCorrect: '🎉 Richtig, 2 Sterne!',
      feedbackWrong: '💪 Zähl nochmal!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.counting,
      questionEmoji: '🐶🐶🐶🐶',
      questionText: 'Wie viele Hunde siehst du?',
      options: ['3', '4', '5', '2'],
      correctAnswer: '4',
      feedbackCorrect: '🌟 Super, 4 Hunde!',
      feedbackWrong: '💪 Zähl die Hunde!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.counting,
      questionEmoji: '🌸🌸🌸🌸🌸',
      questionText: 'Wie viele Blumen siehst du?',
      options: ['4', '5', '6', '3'],
      correctAnswer: '5',
      feedbackCorrect: '🎊 Wow, 5 Blumen!',
      feedbackWrong: '💪 Zähl die Blumen!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '1️⃣',
      questionText: 'Welche Zahl ist größer als 1?',
      options: ['2', '0', '1', '🌸'],
      correctAnswer: '2',
      feedbackCorrect: '🌟 2 ist größer!',
      feedbackWrong: '💪 Nochmal überlegen!',
    ),
    // ── Neue Aufgabentypen ──────────────────────────────────────────
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '🍎🍌🍎🍌🍎❓',
      questionText: 'Was kommt als nächstes?',
      options: ['🍌', '🍎', '🍇', '🍊'],
      correctAnswer: '🍌',
      feedbackCorrect: '🌟 Richtig, Banane!',
      feedbackWrong: '💪 Schau dir das Muster an!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '🔴🔵🔴🔵🔴❓',
      questionText: 'Welche Farbe kommt jetzt?',
      options: ['🔵', '🔴', '🟡', '🟢'],
      correctAnswer: '🔵',
      feedbackCorrect: '🎉 Blau ist richtig!',
      feedbackWrong: '💪 Rot, Blau, Rot, Blau...',
    ),
    const _EarlyQuestion(
      type: _QuestionType.sizeOrder,
      questionEmoji: '🐭🐶🐘',
      questionText: 'Tippe vom Kleinsten zum Größten!',
      options: ['🐘', '🐭', '🐶'],
      correctAnswer: '🐭🐶🐘',
      orderedAnswers: ['🐭', '🐶', '🐘'],
      feedbackCorrect: '🌟 Perfekt sortiert!',
      feedbackWrong: '💪 Maus, Hund, Elefant!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.sizeOrder,
      questionEmoji: '🍓🍉🫐',
      questionText: 'Was ist am kleinsten? Tippe der Reihe nach!',
      options: ['🍉', '🫐', '🍓'],
      correctAnswer: '🫐🍓🍉',
      orderedAnswers: ['🫐', '🍓', '🍉'],
      feedbackCorrect: '🎊 Super sortiert!',
      feedbackWrong: '💪 Blaubeere, Erdbeere, Melone!',
    ),
  ],

  'Deutsch': [
    const _EarlyQuestion(
      type: _QuestionType.anlaut,
      questionEmoji: '🐱',
      questionText: 'Womit fängt KATZE an?',
      options: ['K', 'M', 'A', 'T'],
      correctAnswer: 'K',
      feedbackCorrect: '🌟 K wie Katze!',
      feedbackWrong: '💪 K-K-Katze!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.anlaut,
      questionEmoji: '🐶',
      questionText: 'Womit fängt HUND an?',
      options: ['B', 'H', 'D', 'S'],
      correctAnswer: 'H',
      feedbackCorrect: '🎉 H wie Hund!',
      feedbackWrong: '💪 H-H-Hund!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.anlaut,
      questionEmoji: '🍎',
      questionText: 'Womit fängt APFEL an?',
      options: ['O', 'E', 'A', 'I'],
      correctAnswer: 'A',
      feedbackCorrect: '🌟 A wie Apfel!',
      feedbackWrong: '💪 A-A-Apfel!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.anlaut,
      questionEmoji: '🌞',
      questionText: 'Womit fängt SONNE an?',
      options: ['S', 'M', 'T', 'N'],
      correctAnswer: 'S',
      feedbackCorrect: '🎊 S wie Sonne!',
      feedbackWrong: '💪 S-S-Sonne!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.anlaut,
      questionEmoji: '🐠',
      questionText: 'Womit fängt FISCH an?',
      options: ['V', 'W', 'F', 'B'],
      correctAnswer: 'F',
      feedbackCorrect: '🌟 F wie Fisch!',
      feedbackWrong: '💪 F-F-Fisch!',
    ),
    // ── Neue Aufgabentypen ──────────────────────────────────────────
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: 'A B A B A ❓',
      questionText: 'Welcher Buchstabe kommt jetzt?',
      options: ['A', 'B', 'C', 'D'],
      correctAnswer: 'B',
      feedbackCorrect: '🌟 B ist richtig!',
      feedbackWrong: '💪 A, B, A, B, A...',
    ),
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '🐱🐶🐰🚗',
      questionText: 'Was passt nicht dazu?',
      options: ['🐱', '🐶', '🐰', '🚗'],
      correctAnswer: '🚗',
      feedbackCorrect: '🎉 Das Auto ist kein Tier!',
      feedbackWrong: '💪 Drei sind Tiere, eins nicht!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '🍎🍌🍊🎸',
      questionText: 'Eins gehört nicht dazu!',
      options: ['🍎', '🍌', '🍊', '🎸'],
      correctAnswer: '🎸',
      feedbackCorrect: '🌟 Die Gitarre ist kein Obst!',
      feedbackWrong: '💪 Drei Früchte und eine Gitarre!',
    ),
  ],

  'FarbenFormen': [
    // Farben erkennen
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🔴',
      questionText: 'Welche Farbe siehst du?',
      options: ['Rot', 'Blau', 'Gelb', 'Grün'],
      correctAnswer: 'Rot',
      feedbackCorrect: '🌟 Richtig, das ist Rot!',
      feedbackWrong: '💪 Das ist Rot 🔴!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🔵',
      questionText: 'Welche Farbe siehst du?',
      options: ['Rot', 'Blau', 'Gelb', 'Grün'],
      correctAnswer: 'Blau',
      feedbackCorrect: '🎉 Richtig, das ist Blau!',
      feedbackWrong: '💪 Das ist Blau 🔵!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🟡',
      questionText: 'Was hat diese Farbe?',
      options: ['🍓', '🍋', '🍀', '🫐'],
      correctAnswer: '🍋',
      feedbackCorrect: '🌟 Die Zitrone ist gelb!',
      feedbackWrong: '💪 Die Zitrone 🍋 ist gelb!',
    ),
    // Formen erkennen
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '⭕',
      questionText: 'Was hat die gleiche Form?',
      options: ['🪟', '📦', '🌕', '📐'],
      correctAnswer: '🌕',
      feedbackCorrect: '🌟 Der Mond ist auch rund!',
      feedbackWrong: '💪 Ein Kreis ist rund wie der Mond 🌕!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🟦',
      questionText: 'Was hat die gleiche Form wie das Quadrat?',
      options: ['🌕', '🟦', '🔺', '🪟'],
      correctAnswer: '🟦',
      feedbackCorrect: '🎊 Genau, ein Quadrat!',
      feedbackWrong: '💪 Das Quadrat hat 4 gleiche Seiten!',
    ),
    // Farb-Muster
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '🔴🔵🔴🔵🔴❓',
      questionText: 'Welche Farbe kommt jetzt?',
      options: ['🔵', '🔴', '🟡', '🟢'],
      correctAnswer: '🔵',
      feedbackCorrect: '🎉 Blau kommt jetzt!',
      feedbackWrong: '💪 Rot, Blau, Rot, Blau...',
    ),
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '🟡🟢🟡🟢🟡❓',
      questionText: 'Was kommt als nächstes?',
      options: ['🟡', '🟢', '🔴', '🔵'],
      correctAnswer: '🟢',
      feedbackCorrect: '🌟 Grün ist richtig!',
      feedbackWrong: '💪 Gelb, Grün, Gelb, Grün...',
    ),
    // Odd one out nach Farbe/Form
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '🔴🍓🌹🔵',
      questionText: 'Was ist nicht rot?',
      options: ['🔴', '🍓', '🌹', '🔵'],
      correctAnswer: '🔵',
      feedbackCorrect: '🎉 Blau ist nicht rot!',
      feedbackWrong: '💪 Drei davon sind rot!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '⭕🌕🍕🔺',
      questionText: 'Was ist nicht rund?',
      options: ['⭕', '🌕', '🍕', '🔺'],
      correctAnswer: '🔺',
      feedbackCorrect: '🌟 Das Dreieck ist nicht rund!',
      feedbackWrong: '💪 Drei sind rund!',
    ),
    // Größen vergleichen
    const _EarlyQuestion(
      type: _QuestionType.sizeOrder,
      questionEmoji: '🔵🟤⚫',
      questionText: 'Welcher Kreis ist am kleinsten? Tippe der Reihe nach!',
      options: ['🔵', '🟤', '⚫'],
      correctAnswer: '⚫🟤🔵',
      orderedAnswers: ['⚫', '🟤', '🔵'],
      feedbackCorrect: '🎊 Klein, mittel, groß!',
      feedbackWrong: '💪 Tippe den kleinsten zuerst!',
    ),
  ],

  'Logik': [
    // Zugehörigkeit
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '🍎🍌🍓🚗',
      questionText: 'Was passt nicht dazu?',
      options: ['🍎', '🍌', '🍓', '🚗'],
      correctAnswer: '🚗',
      feedbackCorrect: '🌟 Das Auto ist kein Obst!',
      feedbackWrong: '💪 Drei sind Früchte!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '🐶🐱🐟✏️',
      questionText: 'Was ist kein Tier?',
      options: ['🐶', '🐱', '🐟', '✏️'],
      correctAnswer: '✏️',
      feedbackCorrect: '🎉 Der Stift ist kein Tier!',
      feedbackWrong: '💪 Drei sind Tiere!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '🌧️☀️❄️🍕',
      questionText: 'Was ist kein Wetter?',
      options: ['🌧️', '☀️', '❄️', '🍕'],
      correctAnswer: '🍕',
      feedbackCorrect: '🌟 Pizza ist kein Wetter!',
      feedbackWrong: '💪 Drei sind Wetterarten!',
    ),
    // Muster
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '🐶🐱🐶🐱🐶❓',
      questionText: 'Welches Tier kommt jetzt?',
      options: ['🐶', '🐱', '🐰', '🐸'],
      correctAnswer: '🐱',
      feedbackCorrect: '🌟 Katze kommt jetzt!',
      feedbackWrong: '💪 Hund, Katze, Hund, Katze...',
    ),
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '1️⃣2️⃣1️⃣2️⃣1️⃣❓',
      questionText: 'Was kommt als nächstes?',
      options: ['1️⃣', '2️⃣', '3️⃣', '0️⃣'],
      correctAnswer: '2️⃣',
      feedbackCorrect: '🎉 Die Zwei kommt!',
      feedbackWrong: '💪 Eins, Zwei, Eins, Zwei...',
    ),
    // Größen & Reihenfolgen
    const _EarlyQuestion(
      type: _QuestionType.sizeOrder,
      questionEmoji: '🐜🐇🐻',
      questionText: 'Vom Kleinsten zum Größten!',
      options: ['🐻', '🐜', '🐇'],
      correctAnswer: '🐜🐇🐻',
      orderedAnswers: ['🐜', '🐇', '🐻'],
      feedbackCorrect: '🎊 Ameise, Hase, Bär – perfekt!',
      feedbackWrong: '💪 Ameise ist am kleinsten!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.sizeOrder,
      questionEmoji: '🌱🌿🌳',
      questionText: 'Was ist am kleinsten? Tippe der Reihe nach!',
      options: ['🌳', '🌱', '🌿'],
      correctAnswer: '🌱🌿🌳',
      orderedAnswers: ['🌱', '🌿', '🌳'],
      feedbackCorrect: '🌟 Keim, Pflanze, Baum!',
      feedbackWrong: '💪 Der Keim ist am kleinsten!',
    ),
    // Zuordnen
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '☀️',
      questionText: 'Was gehört zur Sonne?',
      options: ['🌊', '☀️', '❄️', '🌙'],
      correctAnswer: '☀️',
      feedbackCorrect: '🎉 Die Sonne ist warm und hell!',
      feedbackWrong: '💪 Die Sonne scheint!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🚗🚌🚲✈️',
      questionText: 'Womit kannst du fliegen?',
      options: ['🚗', '🚌', '🚲', '✈️'],
      correctAnswer: '✈️',
      feedbackCorrect: '🌟 Mit dem Flugzeug fliegt man!',
      feedbackWrong: '💪 Das Flugzeug fliegt ✈️!',
    ),
  ],
};

// ============================================================================
// QUIZ SCREEN
// ============================================================================

class EarlyLearnerQuizScreen extends ConsumerStatefulWidget {
  final String subject;
  final String subjectEmoji;
  final List<Color> subjectColors;

  const EarlyLearnerQuizScreen({
    super.key,
    required this.subject,
    required this.subjectEmoji,
    required this.subjectColors,
  });

  @override
  ConsumerState<EarlyLearnerQuizScreen> createState() =>
      _EarlyLearnerQuizScreenState();
}

class _EarlyLearnerQuizScreenState extends ConsumerState<EarlyLearnerQuizScreen>
    with TickerProviderStateMixin {
  List<_EarlyQuestion> _questions = [];
  int _currentIndex = 0;
  int _correctAnswers = 0;
  bool _isFinished = false;
  bool _showFeedback = false;
  bool _wasCorrect = false;
  String _feedbackText = '';

  /// Pro-Frage-Ergebnis: true = richtig, false = falsch, null = unbeantwortet
  List<bool?> _stepResults = [];

  /// Für sizeOrder: bisher getippte Reihenfolge
  List<String> _sizeOrderTaps = [];

  /// Schatzkiste anzeigen (vor dem Finish-Screen, bei ≥ 4/5 richtig)
  bool _showTreasureChest = false;

  // Animation Controllers
  late AnimationController _feedbackController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnim;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  // Konfetti
  late ConfettiController _confettiController;
  late ConfettiController _finishConfettiController;

  // Tracking
  LearningTimeTracker? _timeTracker;

  // Child-ID für TTS Settings
  String? _childId;

  @override
  void initState() {
    super.initState();

    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    _childId = child?.id;

    if (child != null && user != null) {
      _timeTracker = LearningTimeTracker(userId: user.uid, childId: child.id);
      _timeTracker!.startTracking();
    }

    // Feedback-Animation (für das Overlay)
    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Bounce bei richtiger Antwort
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    // Shake bei falscher Antwort
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    // Konfetti-Controller
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _finishConfettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );

    _loadQuestions();
  }

  void _loadQuestions() {
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;

    // Versuche KI-generierte Fragen zu laden
    if (child != null && user != null) {
      _loadAiQuestions(user.uid, child);
    } else {
      _loadStaticQuestions();
    }
  }

  Future<void> _loadAiQuestions(String userId, dynamic child) async {
    try {
      final repo = ref.read(earlyLearnerQuestionRepoProvider);
      final aiQuestions = await repo.getQuestions(
        userId: userId,
        childId: child.id,
        child: child,
        subject: widget.subject,
        count: 5,
      );

      if (aiQuestions.isNotEmpty && mounted) {
        final converted = aiQuestions
            .map(_convertAiQuestion)
            .map(_ensureFourOptions)
            .toList();
        setState(() {
          _questions = converted;
          _stepResults = List.filled(_questions.length, null);
        });
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _questions.isNotEmpty) _speakCurrentQuestion();
        });
        return;
      }
    } catch (e) {
      print('⚠️ EarlyQuiz: KI-Fragen nicht verfügbar, nutze statische: $e');
    }
    // Fallback
    _loadStaticQuestions();
  }

  void _loadStaticQuestions() {
    final bank = _questionBank[widget.subject] ?? _questionBank['Mathe']!;
    final shuffled = List<_EarlyQuestion>.from(bank)..shuffle();
    setState(() {
      _questions = shuffled.take(5).map(_ensureFourOptions).toList();
      _stepResults = List.filled(_questions.length, null);
    });

    // Erste Frage nach kurzem Delay vorlesen
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _questions.isNotEmpty) {
        _speakCurrentQuestion();
      }
    });
  }

  /// Stellt sicher dass eine Frage immer genau 4 Antwortoptionen hat.
  /// Füllt fehlende Optionen mit typgerechten Distraktoren auf.
  _EarlyQuestion _ensureFourOptions(_EarlyQuestion q) {
    if (q.options.length == 4) return q;
    // sizeOrder braucht keine 4 Standard-Optionen
    if (q.type == _QuestionType.sizeOrder) return q;

    final opts = List<String>.from(q.options);

    // Sicherstellen dass correctAnswer enthalten ist
    if (!opts.contains(q.correctAnswer)) opts.insert(0, q.correctAnswer);

    // Passende Distraktoren je nach Inhaltstyp
    final isNumber = opts.every((o) => RegExp(r'^\d+$').hasMatch(o));
    final isLetter = opts.every(
      (o) => o.length == 1 && RegExp(r'[A-ZÄÖÜa-zäöü]').hasMatch(o),
    );

    final numberPool = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'];
    final letterPool = [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'K',
      'L',
      'M',
      'N',
      'O',
      'P',
      'R',
      'S',
      'T',
    ];
    final emojiPool = [
      '🌟',
      '🎈',
      '🌈',
      '🦄',
      '🍀',
      '🌙',
      '🎯',
      '🚀',
      '💎',
      '🎪',
    ];

    final pool = isNumber
        ? numberPool
        : isLetter
        ? letterPool
        : emojiPool;

    while (opts.length < 4) {
      final candidate = pool.firstWhere(
        (f) => !opts.contains(f),
        orElse: () => '❓',
      );
      opts.add(candidate);
    }

    // Auf 4 kürzen falls mehr vorhanden (correctAnswer immer behalten)
    if (opts.length > 4) {
      final idx = opts.indexOf(q.correctAnswer);
      if (idx > 3) {
        opts.removeAt(idx);
        opts.insert(0, q.correctAnswer);
      }
      opts.removeRange(4, opts.length);
    }

    opts.shuffle();

    return _EarlyQuestion(
      type: q.type,
      questionEmoji: q.questionEmoji,
      questionText: q.questionText,
      options: opts,
      correctAnswer: q.correctAnswer,
      feedbackCorrect: q.feedbackCorrect,
      feedbackWrong: q.feedbackWrong,
      orderedAnswers: q.orderedAnswers,
    );
  }

  /// Konvertiert eine KI-generierte Frage in das interne _EarlyQuestion-Format.
  _EarlyQuestion _convertAiQuestion(EarlyAiQuestion q) {
    _QuestionType type;
    switch (q.type) {
      case 'counting':
        type = _QuestionType.counting;
        break;
      case 'anlaut':
        type = _QuestionType.anlaut;
        break;
      case 'pattern':
        type = _QuestionType.pattern;
        break;
      case 'oddOneOut':
        type = _QuestionType.oddOneOut;
        break;
      case 'sizeOrder':
        type = _QuestionType.sizeOrder;
        break;
      default:
        type = _QuestionType.imageChoice;
    }

    return _EarlyQuestion(
      type: type,
      questionEmoji: q.questionEmoji,
      questionText: q.questionText,
      options: q.options,
      correctAnswer: q.correctAnswer,
      feedbackCorrect: q.feedbackCorrect,
      feedbackWrong: q.feedbackWrong,
      orderedAnswers: q.orderedAnswers,
    );
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _bounceController.dispose();
    _shakeController.dispose();
    _confettiController.dispose();
    _finishConfettiController.dispose();
    _timeTracker?.stopTracking();
    // TTS stoppen BEVOR super.dispose() – danach ist ref ungültig
    try {
      ref.read(ttsControllerProvider.notifier).stop();
    } catch (_) {
      // ref bereits ungültig – kein Problem, TTS stoppt von selbst
    }
    super.dispose();
  }

  // ── TTS Hilfsmethoden ─────────────────────────────────────────────────────

  bool get _ttsEnabled {
    if (_childId == null) return false;
    return ref.read(ttsSettingsProvider(_childId!));
  }

  void _speakCurrentQuestion() {
    if (!_ttsEnabled || _questions.isEmpty) return;
    final question = _questions[_currentIndex];
    ref
        .read(ttsControllerProvider.notifier)
        .speakQuestion(question.questionText);
  }

  void _speakFeedback(String text) {
    if (!_ttsEnabled) return;
    ref.read(ttsControllerProvider.notifier).speakFeedback(text);
  }

  void _speakResult() {
    if (!_ttsEnabled) return;
    ref
        .read(ttsControllerProvider.notifier)
        .speakResult(correct: _correctAnswers, total: _questions.length);
  }

  // ── Antwort-Logik ─────────────────────────────────────────────────────────

  Future<void> _checkAnswer(String selected) async {
    if (_showFeedback) return;

    final question = _questions[_currentIndex];
    final correct = selected == question.correctAnswer;

    setState(() {
      _showFeedback = true;
      _wasCorrect = correct;
      _feedbackText = correct
          ? question.feedbackCorrect
          : question.feedbackWrong;
      if (correct) _correctAnswers++;
      _stepResults[_currentIndex] = correct;
    });

    if (correct) {
      // ── Richtige Antwort ──────────────────────────────────────────
      HapticFeedback.lightImpact();
      _bounceController.forward().then((_) => _bounceController.reverse());
      _confettiController.play();

      // XP vergeben
      final child = ref.read(activeChildProvider);
      final user = ref.read(authStateChangesProvider).value;
      if (child != null && user != null) {
        try {
          await ref
              .read(xpServiceProvider)
              .addXP(userId: user.uid, childId: child.id, xpToAdd: 5);
        } catch (_) {}
      }
    } else {
      // ── Falsche Antwort ───────────────────────────────────────────
      HapticFeedback.heavyImpact();
      _shakeController.forward().then((_) => _shakeController.reset());
    }

    // Feedback vorlesen
    _speakFeedback(_feedbackText);

    // Feedback-Overlay Animation
    _feedbackController.forward().then((_) => _feedbackController.reverse());

    // Mindest-Anzeigezeit: 1800ms ODER bis TTS fertig ist – je was länger dauert
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    // Warten bis TTS fertig gesprochen hat (max. 4 weitere Sekunden)
    if (_ttsEnabled) {
      int waitMs = 0;
      while (waitMs < 4000 &&
          mounted &&
          ref.read(ttsControllerProvider).isSpeaking) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitMs += 100;
      }
    }
    if (!mounted) return;

    setState(() => _showFeedback = false);

    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _sizeOrderTaps = []; // Reset für nächste Frage
      });
      // Nächste Frage vorlesen (kurzer Delay damit Übergang sichtbar ist)
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _speakCurrentQuestion();
      });
    } else {
      _timeTracker?.stopTracking();

      if (_correctAnswers >= 4) {
        // Schatzkiste zeigen VOR dem Finish-Screen
        setState(() => _showTreasureChest = true);
      } else {
        setState(() => _isFinished = true);
        // Ergebnis vorlesen
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _speakResult();
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isFinished) return _buildFinishScreen();

    // Schatzkiste (vor dem Finish-Screen)
    if (_showTreasureChest) {
      final earnedStars = _correctAnswers * 2;
      final isPerfect = _correctAnswers == _questions.length;
      return Scaffold(
        body: TreasureChestOverlay(
          earnedStars: earnedStars,
          isPerfect: isPerfect,
          onDismiss: () {
            setState(() {
              _showTreasureChest = false;
              _isFinished = true;
            });
            // Ergebnis vorlesen + Konfetti nach Schatzkiste
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                _speakResult();
                _finishConfettiController.play();
              }
            });
          },
        ),
      );
    }

    final question = _questions[_currentIndex];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [widget.subjectColors.first, widget.subjectColors.last],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 12),
                  Expanded(child: _buildQuestionArea(question)),
                ],
              ),
              // Feedback Overlay
              if (_showFeedback) _buildFeedbackOverlay(),
              // Konfetti (von oben Mitte)
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  numberOfParticles: 15,
                  maxBlastForce: 20,
                  minBlastForce: 8,
                  emissionFrequency: 0.05,
                  gravity: 0.2,
                  colors: const [
                    Color(0xFFFFD700), // Gold
                    Color(0xFFFFA500), // Orange
                    Color(0xFFFF6B6B), // Rot
                    Color(0xFF4ECDC4), // Türkis
                    Color(0xFFFFE66D), // Gelb
                    Color(0xFFFF69B4), // Pink
                  ],
                  createParticlePath: _starPath,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Erzeugt sternförmige Konfetti-Partikel
  Path _starPath(Size size) {
    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width / 2;
    final innerR = size.width / 4;

    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 72 - 90) * pi / 180;
      final innerAngle = ((i * 72) + 36 - 90) * pi / 180;

      if (i == 0) {
        path.moveTo(
          cx + outerR * cos(outerAngle),
          cy + outerR * sin(outerAngle),
        );
      } else {
        path.lineTo(
          cx + outerR * cos(outerAngle),
          cy + outerR * sin(outerAngle),
        );
      }
      path.lineTo(cx + innerR * cos(innerAngle), cy + innerR * sin(innerAngle));
    }
    path.close();
    return path;
  }

  // ── Header mit Avatar-Fortschritt ─────────────────────────────────────────

  Widget _buildHeader() {
    final child = ref.watch(activeChildProvider);
    final ttsState = ref.watch(ttsControllerProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Zurück-Button
          GestureDetector(
            onTap: () {
              ref.read(ttsControllerProvider.notifier).stop();
              Navigator.pop(context);
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Avatar-Fortschrittsanzeige ─────────────────────────────
          Expanded(
            child: AvatarProgressBar(
              totalSteps: _questions.length,
              currentStep: _currentIndex,
              stepResults: _stepResults,
              isFinished: _isFinished,
              correctCount: _correctAnswers,
              avatarId: child?.selectedAvatar,
              childName: child?.name ?? '',
              subjectColor: widget.subjectColors.first,
            ),
          ),

          const SizedBox(width: 8),

          // Lautsprecher-Button (erneut vorlesen)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _speakCurrentQuestion();
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                ttsState.isSpeaking
                    ? Icons.volume_up_rounded
                    : Icons.volume_up_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Frage-Bereich ─────────────────────────────────────────────────────────

  Widget _buildQuestionArea(_EarlyQuestion question) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // ── Frage-Karte (mit Shake-Animation bei Fehler) ────────────
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) {
              final shakeOffset = sin(_shakeAnim.value * pi * 3) * 8;
              return Transform.translate(
                offset: Offset(_wasCorrect ? 0 : shakeOffset, 0),
                child: child,
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Typ-Hinweis
                  _buildTypeHint(question.type),
                  const SizedBox(height: 16),
                  // Frage-Emoji: 2×2 Grid für oddOneOut, sonst einzeiliger Text
                  ScaleTransition(
                    scale: _bounceAnim,
                    child: question.type == _QuestionType.oddOneOut
                        ? _buildOddOneOutGrid(question.questionEmoji)
                        : Text(
                            question.questionEmoji,
                            style: const TextStyle(fontSize: 72),
                            textAlign: TextAlign.center,
                          ),
                  ),
                  const SizedBox(height: 14),
                  // Frage-Text
                  Text(
                    question.questionText,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Antwort-Buttons ─────────────────────────────────────────
          Expanded(
            child: question.type == _QuestionType.sizeOrder
                ? _buildSizeOrderArea(question)
                : _buildAnswerGrid(question),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeHint(_QuestionType type) {
    String emoji;
    String hint;
    switch (type) {
      case _QuestionType.anlaut:
        emoji = '👂';
        hint = 'Welcher Buchstabe?';
        break;
      case _QuestionType.counting:
        emoji = '🔢';
        hint = 'Wie viele?';
        break;
      case _QuestionType.wordToImage:
        emoji = '🔍';
        hint = 'Was passt dazu?';
        break;
      case _QuestionType.imageChoice:
        emoji = '👆';
        hint = 'Tippe auf die Antwort!';
        break;
      case _QuestionType.pattern:
        emoji = '🔮';
        hint = 'Was kommt als nächstes?';
        break;
      case _QuestionType.oddOneOut:
        emoji = '🤔';
        hint = 'Was passt nicht?';
        break;
      case _QuestionType.sizeOrder:
        emoji = '📏';
        hint = 'Tippe in der Reihenfolge!';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: widget.subjectColors.first.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            hint,
            style: TextStyle(
              fontSize: 13,
              color: widget.subjectColors.first,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Rendert die 4 Emojis einer oddOneOut-Frage als sauberes 2×2 Grid.
  /// Parst den questionEmoji-String der verschiedene Formate haben kann:
  /// "🍎 🍌 🍓 🚗" oder "🍎🍌🍓🚗" oder als kommaseparierten String.
  Widget _buildOddOneOutGrid(String emojiString) {
    // Klammern vorab entfernen – Sicherheitsnetz falls _extractEmojis sie übersieht
    final input = emojiString
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .trim();

    final emojis = _extractEmojis(input);

    if (emojis.length < 2) {
      return Text(input, style: const TextStyle(fontSize: 56));
    }

    // Auf 4 normieren
    while (emojis.length < 4) emojis.add('❓');
    final display = emojis.take(4).toList();

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.1,
      children: display
          .map(
            (e) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
              ),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 48)),
              ),
            ),
          )
          .toList(),
    );
  }

  /// Extrahiert einzelne Emojis aus einem String.
  /// Unterstützt: leerzeichen-getrennt, komma-getrennt, direkt aneinandergereiht,
  /// sowie Strings mit eckigen Klammern wie "[🔴, 🔵, 🟢, 3️⃣]".
  List<String> _extractEmojis(String input) {
    // Schritt 1: JSON-Array-Notation komplett bereinigen
    String cleaned = input
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();

    // Schritt 2: Komma- oder leerzeichen-getrennte Teile versuchen
    final parts = cleaned
        .replaceAll(',', ' ')
        .split(' ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.length >= 2) return parts;

    // Schritt 3: Fallback – Emojis via Characters-Grapheme-Cluster extrahieren
    // Nutzt Dart's String.characters falls verfügbar, sonst Rune-Annäherung
    final result = <String>[];
    final chars = cleaned.runes.toList();
    int i = 0;
    while (i < chars.length) {
      final cp = chars[i];
      if (cp >= 0x1F300 ||
          cp == 0x2764 ||
          (cp >= 0x2600 && cp <= 0x27BF) ||
          cp >= 0x1F900) {
        String emoji = String.fromCharCode(cp);
        i++;
        // ZWJ-Sequences und Variation Selectors anhängen
        while (i < chars.length &&
            (chars[i] == 0xFE0F ||
                chars[i] == 0x200D ||
                chars[i] == 0x20E3 ||
                chars[i] >= 0xDC00)) {
          emoji += String.fromCharCode(chars[i]);
          i++;
        }
        result.add(emoji);
      } else {
        i++;
      }
    }
    return result.isNotEmpty ? result : (parts.isNotEmpty ? parts : [cleaned]);
  }

  Widget _buildAnswerGrid(_EarlyQuestion question) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: question.options
          .map(
            (opt) => _AnswerTile(
              text: opt,
              colors: widget.subjectColors,
              onTap: () => _checkAnswer(opt),
              enabled: !_showFeedback,
            ),
          )
          .toList(),
    );
  }

  // ── Size Order: Reihenfolge-Tipp-UI ─────────────────────────────────────

  Widget _buildSizeOrderArea(_EarlyQuestion question) {
    return Column(
      children: [
        // Zeige bisherige Taps als Reihenfolge-Anzeige
        if (_sizeOrderTaps.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < _sizeOrderTaps.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  Text(_sizeOrderTaps[i], style: const TextStyle(fontSize: 32)),
                ],
              ],
            ),
          ),

        // Antwort-Buttons (noch nicht getippte)
        Expanded(
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: question.options.map((opt) {
                final alreadyTapped = _sizeOrderTaps.contains(opt);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: alreadyTapped ? 0.3 : 1.0,
                      child: _AnswerTile(
                        text: opt,
                        colors: widget.subjectColors,
                        onTap: () => _handleSizeOrderTap(opt, question),
                        enabled: !_showFeedback && !alreadyTapped,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  void _handleSizeOrderTap(String tapped, _EarlyQuestion question) {
    if (_showFeedback) return;

    final ordered = question.orderedAnswers!;
    final nextExpected = ordered[_sizeOrderTaps.length];

    HapticFeedback.selectionClick();

    if (tapped == nextExpected) {
      // Richtiger Tap in der Reihenfolge
      setState(() => _sizeOrderTaps.add(tapped));
      HapticFeedback.lightImpact();

      // Alle getippt? → Prüfen
      if (_sizeOrderTaps.length == ordered.length) {
        _checkAnswer(ordered.join());
        // Reset für nächste sizeOrder-Frage
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _sizeOrderTaps = []);
        });
      }
    } else {
      // Falsche Reihenfolge → sofort als Fehler werten
      HapticFeedback.heavyImpact();
      setState(() => _sizeOrderTaps = []); // Reset
      _checkAnswer('__wrong__'); // Erzwingt falsches Ergebnis
    }
  }

  // ── Feedback Overlay ──────────────────────────────────────────────────────

  Widget _buildFeedbackOverlay() {
    return AnimatedBuilder(
      animation: _feedbackController,
      builder: (_, __) {
        final opacity = (_feedbackController.value * 2).clamp(0.0, 1.0);
        return Container(
          color: (_wasCorrect ? Colors.green : Colors.deepOrange).withOpacity(
            opacity * 0.88,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: 0.8 + (_feedbackController.value * 0.4),
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _wasCorrect ? '🌟' : '💪',
                        style: const TextStyle(fontSize: 60),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _feedbackText,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Abschluss-Screen ──────────────────────────────────────────────────────

  Widget _buildFinishScreen() {
    final allCorrect = _correctAnswers == _questions.length;
    final earnedStars = _correctAnswers * 2;
    final showConfetti = _correctAnswers >= 4;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [widget.subjectColors.first, widget.subjectColors.last],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Haupt-Emoji
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.elasticOut,
                        builder: (_, v, __) => Transform.scale(
                          scale: v,
                          child: Text(
                            allCorrect ? '🏆' : '🌟',
                            style: const TextStyle(fontSize: 100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Glückwunsch-Text
                      Text(
                        allCorrect ? 'Perfekt!' : 'Super gemacht!',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Ergebnis-Karte
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Sterne als Ergebnis
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _questions.length,
                                (i) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: Duration(
                                      milliseconds: 400 + i * 150,
                                    ),
                                    curve: Curves.elasticOut,
                                    builder: (_, v, __) => Transform.scale(
                                      scale: v,
                                      child: Text(
                                        i < _correctAnswers ? '⭐' : '☆',
                                        style: TextStyle(
                                          fontSize: 36,
                                          color: i < _correctAnswers
                                              ? Colors.amber
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Sterne-Gewinn
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '⭐',
                                    style: TextStyle(fontSize: 28),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '+$earnedStars',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFFF8C00),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Zurück-Button
                      GestureDetector(
                        onTap: () {
                          ref.read(ttsControllerProvider.notifier).stop();
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.home_rounded,
                            color: widget.subjectColors.first,
                            size: 44,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Konfetti beim Abschluss (bei ≥ 4/5 richtig)
              if (showConfetti)
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _finishConfettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    shouldLoop: false,
                    numberOfParticles: 30,
                    maxBlastForce: 25,
                    minBlastForce: 10,
                    emissionFrequency: 0.04,
                    gravity: 0.15,
                    colors: const [
                      Color(0xFFFFD700),
                      Color(0xFFFFA500),
                      Color(0xFFFF6B6B),
                      Color(0xFF4ECDC4),
                      Color(0xFFFFE66D),
                      Color(0xFFFF69B4),
                      Color(0xFF7C4DFF),
                    ],
                    createParticlePath: _starPath,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ANTWORT-KACHEL (unverändert aus v1)
// ============================================================================

class _AnswerTile extends StatefulWidget {
  final String text;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool enabled;

  const _AnswerTile({
    required this.text,
    required this.colors,
    required this.onTap,
    required this.enabled,
  });

  @override
  State<_AnswerTile> createState() => _AnswerTileState();
}

class _AnswerTileState extends State<_AnswerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmoji = _isEmojiText(widget.text);
    final isBuchstabe =
        widget.text.length == 1 &&
        RegExp(r'[A-Za-zÄÖÜäöü]').hasMatch(widget.text);
    final isZahl = RegExp(r'^\d+$').hasMatch(widget.text);

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => _ctrl.forward() : null,
        onTapUp: widget.enabled
            ? (_) {
                _ctrl.reverse();
                HapticFeedback.selectionClick();
                widget.onTap();
              }
            : null,
        onTapCancel: widget.enabled ? () => _ctrl.reverse() : null,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: widget.colors.last.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(
              color: widget.enabled
                  ? widget.colors.first.withOpacity(0.3)
                  : Colors.grey.shade200,
              width: 2,
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: isEmoji
                      ? 42
                      : isBuchstabe
                      ? 48
                      : isZahl
                      ? 40
                      : 18,
                  fontWeight: FontWeight.w800,
                  color: isBuchstabe || isZahl
                      ? widget.colors.first
                      : const Color(0xFF1A1A2E),
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isEmojiText(String text) {
    return text.runes.any(
      (r) =>
          (r >= 0x1F300 && r <= 0x1FAFF) ||
          (r >= 0x2600 && r <= 0x27BF) ||
          (r >= 0xFE00 && r <= 0xFE0F),
    );
  }
}
