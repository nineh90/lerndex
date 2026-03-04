import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex1/src/features/auth/data/auth_repository.dart';
import 'package:lerndex1/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex1/src/features/learning_time/learning_time_tracker.dart';
import 'package:lerndex1/src/features/rewards/data/xp_service.dart';

// ============================================================================
// EARLY LEARNER QUIZ SCREEN – Klasse 1–2
//
// Aufgabentypen:
// 1. BILD-AUSWAHL     → Emoji-Bild + 4 große Emoji-Buttons als Antwort
// 2. ANLAUT-AUFGABE   → Bild hören → welcher Anfangsbuchstabe?
// 3. ZAHLEN-AUFGABE   → Wie viele Punkte siehst du?
// 4. AUDIO-FRAGE      → Frage wird vorgelesen (simuliert via Text-Anzeige)
//
// Kein Fließtext als Antwort – immer Emojis, Buchstaben oder Zahlen.
// ============================================================================

// ── Fragetypen ────────────────────────────────────────────────────────────────

enum _QuestionType {
  imageChoice, // Bild + 4 Bild-Antworten
  anlaut, // Welcher Buchstabe beginnt das Wort?
  counting, // Wie viele sind es?
  wordToImage, // Welches Bild passt zum Wort?
}

class _EarlyQuestion {
  final _QuestionType type;
  final String questionEmoji; // Großes Bild/Emoji als Frage
  final String questionText; // Wird vorgelesen / als Hinweis gezeigt
  final List<String>
  options; // Immer 4 Optionen (Emojis, Buchstaben oder Zahlen)
  final String correctAnswer;
  final String feedbackCorrect;
  final String feedbackWrong;

  const _EarlyQuestion({
    required this.type,
    required this.questionEmoji,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    this.feedbackCorrect = '🌟 Super!',
    this.feedbackWrong = '💪 Nochmal!',
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
  ],

  // Für Klasse 1–2: Englisch wird als Farben- & Tierkunde auf Deutsch vorbereitet.
  // Kein englischer Text – die Kinder lernen Zuordnung durch Bilder.
  'Englisch': [
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🔴',
      questionText: 'Welche Farbe siehst du?',
      options: ['🔵', '🟡', '🔴', '🟢'],
      correctAnswer: '🔴',
      feedbackCorrect: '🌟 Das ist Rot!',
      feedbackWrong: '💪 Das ist Rot 🔴!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🐘',
      questionText: 'Welches Tier ist das?',
      options: ['🦁', '🐘', '🦒', '🐬'],
      correctAnswer: '🐘',
      feedbackCorrect: '🎉 Ein Elefant!',
      feedbackWrong: '💪 Das ist ein Elefant 🐘!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🟡',
      questionText: 'Was hat diese Farbe?',
      options: ['🌊', '🍋', '🍓', '🍀'],
      correctAnswer: '🍋',
      feedbackCorrect: '🌟 Eine Zitrone ist gelb!',
      feedbackWrong: '💪 Die Zitrone ist gelb 🍋!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🐬',
      questionText: 'Wo lebt dieser Delfin?',
      options: ['🌳', '🌊', '🏔️', '🌸'],
      correctAnswer: '🌊',
      feedbackCorrect: '🎊 Im Wasser!',
      feedbackWrong: '💪 Delfine leben im Wasser 🌊!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🦋',
      questionText: 'Was ist das?',
      options: ['🐝', '🐛', '🦋', '🐞'],
      correctAnswer: '🦋',
      feedbackCorrect: '🌟 Ein Schmetterling!',
      feedbackWrong: '💪 Das ist ein Schmetterling 🦋!',
    ),
  ],

  'Sachkunde': [
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🌤️',
      questionText: 'Welches Wetter siehst du?',
      options: ['☀️', '🌤️', '🌧️', '❄️'],
      correctAnswer: '🌤️',
      feedbackCorrect: '🌟 Leicht bewölkt!',
      feedbackWrong: '💪 Schau genau hin!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🐦',
      questionText: 'Was kann dieses Tier?',
      options: ['🏊', '✈️ Fliegen', '🏃', '🛏️'],
      correctAnswer: '✈️ Fliegen',
      feedbackCorrect: '🎉 Vögel können fliegen!',
      feedbackWrong: '💪 Vögel haben Flügel!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🌳',
      questionText: 'Was ist das?',
      options: ['🌊', '🏔️', '🌳', '🌸'],
      correctAnswer: '🌳',
      feedbackCorrect: '🌟 Ein Baum!',
      feedbackWrong: '💪 Das ist ein Baum!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '☀️🌱',
      questionText: 'Was braucht eine Pflanze?',
      options: ['☀️', '🍕', '🎮', '📱'],
      correctAnswer: '☀️',
      feedbackCorrect: '🌟 Sonne und Wasser!',
      feedbackWrong: '💪 Pflanzen brauchen Sonne!',
    ),
    const _EarlyQuestion(
      type: _QuestionType.imageChoice,
      questionEmoji: '🌧️',
      questionText: 'Was passiert bei Regen?',
      options: [
        'Es wird nass 💧',
        'Es schneit ❄️',
        'Es wird heiß 🌡️',
        'Es ist Nacht 🌙',
      ],
      correctAnswer: 'Es wird nass 💧',
      feedbackCorrect: '🎊 Richtig, alles wird nass!',
      feedbackWrong: '💪 Regen macht alles nass!',
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

  late AnimationController _feedbackController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnim;

  LearningTimeTracker? _timeTracker;

  @override
  void initState() {
    super.initState();

    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    if (child != null && user != null) {
      _timeTracker = LearningTimeTracker(userId: user.uid, childId: child.id);
      _timeTracker!.startTracking();
    }

    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    _loadQuestions();
  }

  void _loadQuestions() {
    final bank = _questionBank[widget.subject] ?? _questionBank['Mathe']!;
    final shuffled = List<_EarlyQuestion>.from(bank)..shuffle();
    setState(() {
      _questions = shuffled.take(5).toList();
    });
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _bounceController.dispose();
    _timeTracker?.stopTracking();
    super.dispose();
  }

  Future<void> _checkAnswer(String selected) async {
    if (_showFeedback) return;

    final question = _questions[_currentIndex];
    final correct = selected == question.correctAnswer;

    HapticFeedback.mediumImpact();

    setState(() {
      _showFeedback = true;
      _wasCorrect = correct;
      _feedbackText = correct
          ? question.feedbackCorrect
          : question.feedbackWrong;
      if (correct) _correctAnswers++;
    });

    // Bounce-Animation bei richtig
    if (correct) {
      _bounceController.forward().then((_) => _bounceController.reverse());

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
    }

    _feedbackController.forward().then((_) => _feedbackController.reverse());

    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    setState(() => _showFeedback = false);

    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    } else {
      _timeTracker?.stopTracking();
      setState(() => _isFinished = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isFinished) return _buildFinishScreen();

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
              if (_showFeedback) _buildFeedbackOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Zurück-Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
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
          const SizedBox(width: 12),
          // Fortschritt als Sterne-Punkte
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _questions.length,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: i == _currentIndex ? 32 : 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: i <= _currentIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: i < _currentIndex
                        ? const Center(
                            child: Text('⭐', style: TextStyle(fontSize: 12)),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
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

          // ── Frage-Karte ─────────────────────────────────────────────────
          Container(
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
                // Typ-Hinweis (klein, aber mit Emoji verständlich)
                _buildTypeHint(question.type),
                const SizedBox(height: 16),
                // Großes Frage-Emoji
                ScaleTransition(
                  scale: _bounceAnim,
                  child: Text(
                    question.questionEmoji,
                    style: const TextStyle(fontSize: 72),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 14),
                // Frage-Text (groß, gut lesbar)
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

          const SizedBox(height: 20),

          // ── Antwort-Buttons ─────────────────────────────────────────────
          Expanded(child: _buildAnswerGrid(question)),
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
          child: Center(
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
                      shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
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
                                duration: Duration(milliseconds: 400 + i * 150),
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
                              const Text('⭐', style: TextStyle(fontSize: 28)),
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

                  // Zurück-Button – groß und eindeutig
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.home_rounded,
                            color: widget.subjectColors.first,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Text('🏠', style: const TextStyle(fontSize: 28)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ANTWORT-KACHEL
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
    // Erkennt ob der Text ein Emoji ist (für große Darstellung)
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
    // Heuristik: enthält Emoji-Codepoints
    return text.runes.any(
      (r) =>
          (r >= 0x1F300 && r <= 0x1FAFF) ||
          (r >= 0x2600 && r <= 0x27BF) ||
          (r >= 0xFE00 && r <= 0xFE0F),
    );
  }
}
