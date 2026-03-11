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
import 'package:lerndex/src/features/generated_tasks/data/generated_task_repository.dart';
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/auth/data/profile_repository.dart';
import 'package:lerndex/src/features/rewards/presentation/student_notification_popup.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/rewards_count_provider.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/avatar_progress_bar.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/treasure_chest_overlay.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_finish_service.dart';

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
    // ── Zahlenvergleiche (IMMER zwei Zahlen im Emoji!) ──────────────
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '1️⃣ und 3️⃣',
      questionText: 'Welche Zahl ist größer?',
      options: ['1', '3', '2', '4'],
      correctAnswer: '3',
      feedbackCorrect: '🌟 3 ist größer als 1!',
      feedbackWrong: '💪 3 ist mehr als 1!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🍎🍎 ➕ 🍎',
      questionText: '2 Äpfel und noch 1 – wie viele?',
      options: ['2', '3', '4', '1'],
      correctAnswer: '3',
      feedbackCorrect: '🎉 Richtig, 2 + 1 = 3!',
      feedbackWrong: '💪 Zähle alle zusammen!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '5️⃣ und 8️⃣',
      questionText: 'Welche Zahl ist kleiner?',
      options: ['5', '8', '3', '10'],
      correctAnswer: '5',
      feedbackCorrect: '🌟 Ja, 5 ist kleiner als 8!',
      feedbackWrong: '💪 5 ist weniger als 8!',
    ),
    // ── Zahlen-Muster (NUR Zahlen-Emojis!) ────────────────────────
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '1️⃣2️⃣1️⃣2️⃣1️⃣❓',
      questionText: 'Welche Zahl kommt jetzt?',
      options: ['1', '2', '3', '0'],
      correctAnswer: '2',
      feedbackCorrect: '🎉 Die 2 kommt!',
      feedbackWrong: '💪 1, 2, 1, 2, 1...',
    ),
    const _EarlyQuestion(
      type: _QuestionType.pattern,
      questionEmoji: '1️⃣2️⃣3️⃣4️⃣❓',
      questionText: 'Welche Zahl kommt als nächstes?',
      options: ['5', '4', '6', '3'],
      correctAnswer: '5',
      feedbackCorrect: '🌟 5 kommt nach 4!',
      feedbackWrong: '💪 1, 2, 3, 4... was kommt dann?',
    ),
    const _EarlyQuestion(
      type: _QuestionType.counting,
      questionEmoji: '🐟🐟🐟🐟🐟🐟',
      questionText: 'Wie viele Fische siehst du?',
      options: ['5', '6', '7', '4'],
      correctAnswer: '6',
      feedbackCorrect: '🌟 Genau, 6 Fische!',
      feedbackWrong: '💪 Zähl nochmal ganz langsam!',
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
      questionEmoji: '🐻🍌🐝🎸',
      questionText: 'Was fängt NICHT mit B an?',
      options: ['🐻', '🍌', '🐝', '🎸'],
      correctAnswer: '🎸',
      feedbackCorrect: '🎉 Gitarre fängt mit G an, nicht B!',
      feedbackWrong: '💪 Bär, Banane, Biene – alle mit B!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.oddOneOut,
      questionEmoji: '🐱🍒🐄🌞',
      questionText: 'Was fängt NICHT mit K an?',
      options: ['🐱', '🍒', '🐄', '🌞'],
      correctAnswer: '🌞',
      feedbackCorrect: '🌟 Sonne fängt mit S an!',
      feedbackWrong: '💪 Katze, Kirsche, Kuh – alle mit K!',
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
  bool _finishQuizCalled = false; // Guard gegen Doppelaufruf
  bool _wasCorrect = false;
  bool _showRetryChoice = false;
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

  /// parentTaskRef je Fragen-Index (nur für Eltern-Aufgaben gesetzt)
  final Map<int, String> _parentTaskRefs = {};

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

  // ── Ziel-Fragenanzahl ─────────────────────────────────────────────────────
  static const int _targetQuestionCount = 5;

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
    // ── 1. Eltern-Aufgaben mit höchster Priorität ────────────────────────────
    try {
      final taskRepo = ref.read(generatedTaskRepositoryProvider);
      final subjectEnum = SubjectExtension.fromString(widget.subject);
      final parentQuestions = await taskRepo.getUnansweredApprovedQuestions(
        userId: userId,
        childId: child.id,
        subject: subjectEnum,
      );

      if (parentQuestions.isNotEmpty && mounted) {
        final shuffled = List<GeneratedQuestion>.from(parentQuestions)
          ..shuffle();
        final selected = shuffled.take(_targetQuestionCount).toList();

        final converted = selected.asMap().entries.map((entry) {
          final idx = entry.key;
          final gq = entry.value;
          // parentTaskRef für späteres Tracking speichern
          if (gq.batchId != null) {
            _parentTaskRefs[idx] = '${gq.batchId}/${gq.id}';
          }
          return _ensureFourOptions(
            _EarlyQuestion(
              type: _QuestionType.imageChoice,
              questionEmoji: '📝',
              questionText: gq.question,
              options: gq.options,
              correctAnswer: gq.correctAnswer,
              feedbackCorrect: '🌟 Super gemacht!',
              feedbackWrong: '💪 Versuch es nochmal!',
            ),
          );
        }).toList();

        setState(() {
          _questions = converted;
          _stepResults = List.filled(_questions.length, null);
        });
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _questions.isNotEmpty) _speakCurrentQuestion();
        });
        debugPrint(
          '👨‍👩‍👧 ${selected.length} Eltern-Aufgaben für Early Learner geladen',
        );
        return;
      }
    } catch (e) {
      debugPrint('⚠️ EarlyQuiz: Eltern-Aufgaben nicht verfügbar: $e');
    }

    // ── 2. KI-generierte Fragen ──────────────────────────────────────────────
    //
    // Der Fach-Filter läuft jetzt schon im Repository VOR dem Cachen.
    // Alle Fragen im Cache sind garantiert fachkonform → einfach 5 holen.
    // Statische Fragen NUR als absoluter Fallback (kein Internet etc.)
    //
    try {
      final repo = ref.read(earlyLearnerQuestionRepoProvider);

      final aiQuestions = await repo.getQuestions(
        userId: userId,
        childId: child.id,
        child: child,
        subject: widget.subject,
        count: _targetQuestionCount,
      );

      if (aiQuestions.isNotEmpty && mounted) {
        final converted = aiQuestions
            .map(_convertAiQuestion)
            .map(_ensureFourOptions)
            .toList();

        if (converted.length >= _targetQuestionCount) {
          setState(() {
            _questions = converted.take(_targetQuestionCount).toList();
            _stepResults = List.filled(_questions.length, null);
          });
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted && _questions.isNotEmpty) _speakCurrentQuestion();
          });
          return;
        }

        // Weniger als 5 – trotzdem KI-Fragen nutzen wenn welche da sind
        if (converted.isNotEmpty) {
          debugPrint(
            '⚠️ EarlyQuiz: Nur ${converted.length}/$_targetQuestionCount '
            'KI-Fragen verfügbar → starte mit ${converted.length}',
          );
          setState(() {
            _questions = converted;
            _stepResults = List.filled(_questions.length, null);
          });
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted && _questions.isNotEmpty) _speakCurrentQuestion();
          });

          // Hintergrund: Mehr generieren für nächstes Mal
          repo.getQuestions(
            userId: userId,
            childId: child.id,
            child: child,
            subject: widget.subject,
            count: _targetQuestionCount * 3,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ EarlyQuiz: KI-Fragen nicht verfügbar, nutze statische: $e',
      );
    }

    // ── 3. Statische Fallback-Fragen ─────────────────────────────────────────
    // NUR wenn gar keine KI-Fragen verfügbar sind (kein Internet, Fehler etc.)
    _loadStaticQuestions();
  }

  /// Gibt [count] gefilterte statische Fragen für das aktuelle Fach zurück.
  /// NUR als absoluter Fallback wenn KI nicht verfügbar ist!
  List<_EarlyQuestion> _getStaticQuestions(int count) {
    // 'Zahlen' → 'Mathe', 'Buchstaben' → 'Deutsch' (Dashboard-Aliase)
    final key = _normalizeSubject(widget.subject);
    final bank = _questionBank[key] ?? _questionBank['Mathe']!;
    final filtered = _filterBySubject(bank, key);
    final pool = filtered.isNotEmpty ? filtered : bank;
    final shuffled = List<_EarlyQuestion>.from(pool)..shuffle();
    return shuffled.take(count).map(_ensureFourOptions).toList();
  }

  /// Normalisiert Dashboard-Subject-Aliase auf kanonische interne Namen.
  /// 'Zahlen' → 'Mathe', 'Buchstaben' → 'Deutsch', alles andere unverändert.
  String _normalizeSubject(String subject) {
    switch (subject) {
      case 'Zahlen':
        return 'Mathe';
      case 'Buchstaben':
        return 'Deutsch';
      default:
        return subject;
    }
  }

  void _loadStaticQuestions() {
    final questions = _getStaticQuestions(_targetQuestionCount);
    setState(() {
      _questions = questions;
      _stepResults = List.filled(_questions.length, null);
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _questions.isNotEmpty) _speakCurrentQuestion();
    });
  }

  /// Filtert Fragen nach erlaubten Typen UND Inhalten pro Fach.
  /// Verhindert z.B. Zählen-Aufgaben bei Buchstaben oder Sonnen-Fragen bei Mathe.
  /// Hilfsmethode: Prüft ob alle options reine Zahlen sind
  bool _optionsAreNumbers(List<String> opts) =>
      opts.every((o) => RegExp(r'^\d+$').hasMatch(o));

  /// Hilfsmethode: Prüft ob alle options einzelne Buchstaben sind
  bool _optionsAreLetters(List<String> opts) =>
      opts.every((o) => o.length == 1 && RegExp(r'[A-ZÄÖÜa-zäöü]').hasMatch(o));

  /// Hilfsmethode: Prüft ob questionEmoji Zahlen-Emojis enthält
  bool _emojiHasNumbers(String emoji) =>
      RegExp(r'[0-9]|[1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣0️⃣]').hasMatch(emoji);

  List<_EarlyQuestion> _filterBySubject(
    List<_EarlyQuestion> questions,
    String subject, // erwartet bereits normalisierten Subject-String
  ) {
    // Sicherheits-Normalisierung falls direkt aufgerufen
    final normalized = _normalizeSubject(subject);
    switch (normalized) {
      case 'Mathe':
        return questions.where((q) {
          final text = q.questionText.toLowerCase();

          // Erlaubte Typen für Mathe
          switch (q.type) {
            case _QuestionType.counting:
              // counting ist immer Mathe (Dinge zählen → Zahlen als Antwort)
              return _optionsAreNumbers(q.options);

            case _QuestionType.imageChoice:
              // Muss eindeutigen Zahlen-Bezug haben
              return text.contains('zahl') ||
                  text.contains('größer') ||
                  text.contains('kleiner') ||
                  text.contains('wie viele') ||
                  text.contains('mehr') ||
                  text.contains('weniger') ||
                  text.contains('rechne') ||
                  text.contains('ergebnis') ||
                  _optionsAreNumbers(q.options);

            case _QuestionType.pattern:
              // Muster nur wenn Zahlen oder Mathe-Emojis → options sind Zahlen
              // ODER der questionText explizit Zahlen-Muster anspricht
              return _optionsAreNumbers(q.options) ||
                  _emojiHasNumbers(q.questionEmoji) ||
                  text.contains('zahl') ||
                  text.contains('zähl');

            case _QuestionType.sizeOrder:
              // sizeOrder bei Mathe: options müssen Zahlen sein
              return _optionsAreNumbers(q.options);

            default:
              // oddOneOut, anlaut, wordToImage → nicht für Mathe
              return false;
          }
        }).toList();

      case 'Deutsch':
        return questions.where((q) {
          final text = q.questionText.toLowerCase();

          switch (q.type) {
            case _QuestionType.anlaut:
              // anlaut immer Deutsch wenn options Buchstaben sind
              return _optionsAreLetters(q.options);

            case _QuestionType.pattern:
              // Muster nur wenn options Buchstaben sind
              return _optionsAreLetters(q.options);

            case _QuestionType.oddOneOut:
              // Kein Zahlen-Text, kein Reimen
              return !text.contains('wie viele') &&
                  !text.contains('zähl') &&
                  !text.contains('reimt') &&
                  !text.contains('zahl') &&
                  !text.contains('farbe') &&
                  !text.contains('form') &&
                  !text.contains('rund') &&
                  !text.contains('eckig');

            default:
              // counting, imageChoice, sizeOrder → nicht für Deutsch
              return false;
          }
        }).toList();

      case 'FarbenFormen':
        return questions.where((q) {
          final text = q.questionText.toLowerCase();

          switch (q.type) {
            case _QuestionType.imageChoice:
              // Muss Farb- oder Form-Bezug haben
              return text.contains('farbe') ||
                  text.contains('form') ||
                  text.contains('farb') ||
                  text.contains('rot') ||
                  text.contains('blau') ||
                  text.contains('gelb') ||
                  text.contains('grün') ||
                  text.contains('rund') ||
                  text.contains('eckig') ||
                  text.contains('kreis') ||
                  text.contains('dreieck') ||
                  text.contains('quadrat') ||
                  text.contains('rechteck') ||
                  text.contains('gleiche');

            case _QuestionType.pattern:
              // Muster nur wenn options Farb-Emojis sind (keine Zahlen, keine Buchstaben)
              return !_optionsAreNumbers(q.options) &&
                  !_optionsAreLetters(q.options);

            case _QuestionType.oddOneOut:
              // Farb- oder Form-Kontext
              return !text.contains('buchstab') &&
                  !text.contains('anlaut') &&
                  !text.contains('zahl') &&
                  !text.contains('wie viele') &&
                  (text.contains('nicht') ||
                      text.contains('passt') ||
                      text.contains('farb') ||
                      text.contains('form') ||
                      text.contains('rund') ||
                      text.contains('rot') ||
                      text.contains('blau'));

            case _QuestionType.sizeOrder:
              // sizeOrder bei FarbenFormen: keine Zahlen-Optionen
              return !_optionsAreNumbers(q.options);

            default:
              return false;
          }
        }).toList();

      default:
        return questions;
    }
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

  // ── Quiz-Abschluss: Stats & Rewards ──────────────────────────────────────

  /// Wird einmalig aufgerufen wenn das Quiz endet (direkt oder nach Schatzkiste).
  /// Delegiert an QuizFinishService — keine duplizierte Logik mehr.
  Future<void> _finishQuiz() async {
    if (_finishQuizCalled) return;
    _finishQuizCalled = true;

    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    if (child == null || user == null) return;

    await QuizFinishService.finish(
      ref: ref,
      context: context,
      userId: user.uid,
      childId: child.id,
      isPerfect: _correctAnswers == _questions.length,
      timeTracker: _timeTracker,
    );
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
          // Early Learner (Klasse 1–2): 3 XP pro richtiger Antwort (statt 5)
          // → Level 1→2 benötigt ~20 richtige Antworten (~4 Quizze)
          await ref
              .read(xpServiceProvider)
              .addXP(userId: user.uid, childId: child.id, xpToAdd: 3);
        } catch (_) {}

        // Eltern-Aufgabe als beantwortet markieren (falls vorhanden)
        final parentTaskRef = _parentTaskRefs[_currentIndex];
        if (parentTaskRef != null) {
          try {
            await ref
                .read(generatedTaskRepositoryProvider)
                .markQuestionAnsweredCorrectly(
                  userId: user.uid,
                  parentTaskRef: parentTaskRef,
                );
            debugPrint(
              '✅ Early-Learner Eltern-Aufgabe markiert: $parentTaskRef',
            );
          } catch (_) {}
        }
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

    if (correct) {
      // ── Richtige Antwort: kurz warten, dann auto-advance ─────────────
      await Future.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
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
      _advanceToNext();
    } else {
      // ── Falsche Antwort: kurz warten, dann Retry-Wahl zeigen ─────────
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      if (_ttsEnabled) {
        int waitMs = 0;
        while (waitMs < 3000 &&
            mounted &&
            ref.read(ttsControllerProvider).isSpeaking) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitMs += 100;
        }
      }
      if (!mounted) return;
      setState(() => _showRetryChoice = true);
    }
  }

  /// Geht zur nächsten Frage oder beendet das Quiz.
  void _advanceToNext() {
    setState(() {
      _showFeedback = false;
      _showRetryChoice = false;
    });
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _sizeOrderTaps = [];
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _speakCurrentQuestion();
      });
    } else {
      _timeTracker?.stopTracking();
      if (_correctAnswers >= 4) {
        setState(() => _showTreasureChest = true);
      } else {
        setState(() => _isFinished = true);
        _finishQuiz();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _speakResult();
        });
      }
    }
  }

  /// Wiederholt die aktuelle Frage (nach falscher Antwort).
  void _retryCurrentQuestion() {
    setState(() {
      _showFeedback = false;
      _showRetryChoice = false;
      _sizeOrderTaps = [];
      _stepResults[_currentIndex] = null;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _speakCurrentQuestion();
    });
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
      final earnedXP = _correctAnswers * 3;
      final isPerfect = _correctAnswers == _questions.length;
      return Scaffold(
        body: TreasureChestOverlay(
          earnedStars:
              earnedXP, // Wird als ⭐ angezeigt, entspricht den verdienten XP
          isPerfect: isPerfect,
          onDismiss: () {
            setState(() {
              _showTreasureChest = false;
              _isFinished = true;
            });
            _finishQuiz(); // Stats + Rewards speichern
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
              if (_showFeedback || _showRetryChoice) _buildFeedbackOverlay(),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(height: 8),

                  // ── Frage-Karte (mit Shake-Animation bei Fehler) ─────
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Typ-Hinweis
                          _buildTypeHint(question.type),
                          const SizedBox(height: 12),
                          // Frage-Emoji: dynamische Größe!
                          ScaleTransition(
                            scale: _bounceAnim,
                            child: question.type == _QuestionType.oddOneOut
                                ? _buildOddOneOutGrid(
                                    question.questionEmoji,
                                    question.options,
                                  )
                                : _buildAdaptiveEmoji(question.questionEmoji),
                          ),
                          const SizedBox(height: 10),
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

                  const SizedBox(height: 16),

                  // ── Antwort-Buttons ──────────────────────────────────
                  question.type == _QuestionType.sizeOrder
                      ? SizedBox(
                          height: constraints.maxHeight * 0.4,
                          child: _buildSizeOrderArea(question),
                        )
                      : _buildAnswerGrid(question),

                  // Extra bottom-padding damit nichts von System-Buttons
                  // (Android Navigation Bar) überdeckt wird
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Emoji-Anzeige die sich an die Menge der Emojis anpasst.
  /// Bei wenigen Emojis (z.B. "🍎🍎🍎") → groß (fontSize 72)
  /// Bei vielen Emojis (z.B. "🍎🍎🍎🍎🍎🍎🍎") → kleiner (fontSize 44)
  Widget _buildAdaptiveEmoji(String emoji) {
    final runes = emoji.runes.toList();
    final emojiCount = runes.where((r) => r >= 0x1F300 || r >= 0x2600).length;
    final textLength = emoji.replaceAll(' ', '').length;

    double fontSize;
    if (emojiCount <= 3 || textLength <= 6) {
      fontSize = 72;
    } else if (emojiCount <= 5 || textLength <= 10) {
      fontSize = 56;
    } else if (emojiCount <= 7 || textLength <= 14) {
      fontSize = 44;
    } else {
      fontSize = 36;
    }

    return Text(
      emoji,
      style: TextStyle(fontSize: fontSize),
      textAlign: TextAlign.center,
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
  ///
  /// WICHTIG: Nutzt primär [options] statt [emojiString] zu parsen!
  /// Die options kommen einzeln aus dem JSON-Array und sind immer korrekt
  /// aufgesplittet – im Gegensatz zu questionEmoji das ein einziger String
  /// ist und bei zusammengesetzten Emojis (ZWJ-Sequences) oft falsch
  /// zerlegt wird.
  Widget _buildOddOneOutGrid(String emojiString, List<String> options) {
    // Primär: options verwenden (sind immer korrekt aufgesplittet)
    List<String> display;
    if (options.length >= 4) {
      display = options.take(4).toList();
    } else if (options.length >= 2) {
      // Auffüllen falls weniger als 4
      display = List<String>.from(options);
      while (display.length < 4) {
        display.add('❓');
      }
    } else {
      // Fallback: emojiString als Ganzes anzeigen
      return Text(emojiString, style: const TextStyle(fontSize: 56));
    }

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
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
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
        final opacity = _showRetryChoice
            ? 0.92
            : (_feedbackController.value * 2).clamp(0.0, 1.0);
        final iconScale = _showRetryChoice
            ? 1.2
            : 0.8 + (_feedbackController.value * 0.4);

        return SizedBox.expand(
          child: ColoredBox(
            color: (_wasCorrect ? Colors.green : Colors.deepOrange).withOpacity(
              opacity,
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Emoji-Kreis ───────────────────────────────────────────
                  Transform.scale(
                    scale: iconScale,
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

                  // ── Feedback-Text ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _feedbackText,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // ── Retry-Buttons (nur bei falscher Antwort) ─────────────
                  if (_showRetryChoice) ...[
                    const SizedBox(height: 40),

                    // 🔄 Nochmal-Button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _retryCurrentQuestion();
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🔄', style: TextStyle(fontSize: 32)),
                            const SizedBox(width: 12),
                            Text(
                              'Nochmal!',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.deepOrange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ➡️ Weiter-Button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _advanceToNext();
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white60, width: 2),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('➡️', style: TextStyle(fontSize: 32)),
                            SizedBox(width: 12),
                            Text(
                              'Weiter',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Abschluss-Screen ──────────────────────────────────────────────────────

  Widget _buildFinishScreen() {
    final allCorrect = _correctAnswers == _questions.length;
    final earnedXP = _correctAnswers * 3; // XP werden als ⭐ dargestellt
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
                            // XP-Gewinn als Sterne dargestellt
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
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '+$earnedXP',
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFFF8C00),
                                        ),
                                      ),
                                      Text(
                                        'in diesem Quiz',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.amber.shade700,
                                        ),
                                      ),
                                    ],
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
