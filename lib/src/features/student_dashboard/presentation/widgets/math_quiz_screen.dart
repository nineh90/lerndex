import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:confetti/confetti.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/learning_time/learning_time_tracker.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/avatar_progress_bar.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/treasure_chest_overlay.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_finish_service.dart';
import 'math_task_engine.dart';

// ============================================================================
// MATH QUIZ SCREEN – Klasse 1 & 2
//
// Vollständig lokale Aufgaben (kein KI, kein Firebase-Cache).
// Aufgaben werden algorithmisch generiert → keine Duplikate, keine Fehler.
//
// Aufgabentypen:
//   multipleChoice  – 4 + 3 = ?  →  4 Antwort-Buttons
//   fillBlank       – 4 + __ = 7 →  4 Antwort-Buttons
//   comparison      – 5 __ 8     →  < = > Buttons
//   countDots       – ●●●●● = ?  →  4 Antwort-Buttons
//   numberOrder     – [5,2,8] sortieren → Drag-Reihenfolge tippen
//   numberLine      – Zahlenstrahl: richtige Zahl antippen
//   balanceScale    – Waage: fehlende Zahl finden
// ============================================================================

class MathQuizScreen extends ConsumerStatefulWidget {
  final int grade;
  final List<Color> subjectColors;

  const MathQuizScreen({
    super.key,
    required this.grade,
    required this.subjectColors,
  });

  @override
  ConsumerState<MathQuizScreen> createState() => _MathQuizScreenState();
}

class _MathQuizScreenState extends ConsumerState<MathQuizScreen>
    with TickerProviderStateMixin {
  static const int _questionCount = 5;

  List<MathTask> _tasks = [];
  int _currentIndex = 0;
  int _correctAnswers = 0;
  bool _isFinished = false;
  bool _showFeedback = false;
  bool _wasCorrect = false;
  bool _showRetryChoice = false;
  String _feedbackText = '';
  bool _finishQuizCalled = false;
  bool _showTreasureChest = false;

  List<bool?> _stepResults = [];

  // Für numberOrder: bisher getippte Reihenfolge
  List<String> _orderTaps = [];

  // Für numberLine (Slider)
  double _sliderValue = 0;
  bool _sliderMoved = false;

  // Für drawAnswer
  final GlobalKey _canvasKey = GlobalKey();
  List<List<Offset?>> _drawStrokes = [];
  List<Offset> _currentStroke = [];
  bool _isEvaluating = false;
  int _drawAttempts = 0;
  static const int _maxDrawAttempts = 3;
  GenerativeModel? _aiModel;

  // Animation
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
  String? _childId;

  @override
  void initState() {
    super.initState();
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    _childId = child?.id;

    if (child != null && user != null) {
      _timeTracker = LearningTimeTracker(
        userId: user.uid,
        childId: child.id,
        subject: 'Zahlen',
      );
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

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _finishConfettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );

    _generateTasks();
    _initAI();
  }

  Future<void> _initAI() async {
    try {
      _aiModel = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.0-flash',
        generationConfig: GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 20,
        ),
      );
    } catch (e) {
      debugPrint('MathQuiz: AI init failed: \$e');
    }
  }

  void _generateTasks() {
    final child = ref.read(activeChildProvider);
    final engine = MathTaskEngine(
      grade: widget.grade,
      level: child?.level ?? 1,
    );
    final tasks = engine.generate(_questionCount);
    setState(() {
      _tasks = tasks;
      _stepResults = List.filled(tasks.length, null);
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _speakCurrentQuestion();
    });
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _bounceController.dispose();
    _shakeController.dispose();
    _confettiController.dispose();
    _finishConfettiController.dispose();
    try {
      ref.read(ttsControllerProvider.notifier).stop();
    } catch (_) {}
    super.dispose();
  }

  // ── TTS ───────────────────────────────────────────────────────────────────

  bool get _ttsEnabled {
    if (_childId == null) return false;
    return ref.read(ttsSettingsProvider(_childId!));
  }

  void _speakCurrentQuestion() {
    if (!_ttsEnabled || _tasks.isEmpty) return;
    final task = _tasks[_currentIndex];
    ref.read(ttsControllerProvider.notifier).speakQuestion(_buildTtsText(task));
  }

  /// Baut einen TTS-freundlichen Text – ersetzt Symbole durch Wörter.
  String _buildTtsText(MathTask task) {
    switch (task.type) {
      case MathTaskType.wordProblem:
        return task.questionText; // bereits TTS-freundlich
      case MathTaskType.missingNumber:
        // Lücke vorlesen + Hinweis ob auf- oder absteigend
        final seq = task.sequence ?? [];
        final isDesc = seq.length >= 2 && seq[0] > seq[1];
        final spoken = task.questionText.replaceAll('__', 'Lücke');
        final hint = isDesc
            ? ' – die Reihe wird kleiner!'
            : ' – welche Zahl fehlt?';
        return spoken + hint;
      case MathTaskType.countDots:
        if (task.countEmoji != null && task.countEmoji!.startsWith('MIXED:')) {
          return 'Wie viele sind es zusammen?';
        }
        return task.questionText;
      case MathTaskType.drawAnswer:
        return task.questionText
            .replaceAll(' + ', ' plus ')
            .replaceAll(' - ', ' minus ')
            .replaceAll(' = ?', ' – male die Antwort!');
      case MathTaskType.numberLine:
        return 'Zeige die ${task.lineTarget} auf dem Zahlenstrahl!';
      default:
        return task.questionText
            .replaceAll(' - ', ' minus ')
            .replaceAll(' + ', ' plus ')
            .replaceAll('[?]', 'Lücke')
            .replaceAll('= ?', 'gleich wie viel?');
    }
  }

  void _speakFeedback(String text) {
    if (!_ttsEnabled) return;
    ref.read(ttsControllerProvider.notifier).speakFeedback(text);
  }

  void _speakResult() {
    if (!_ttsEnabled) return;
    ref
        .read(ttsControllerProvider.notifier)
        .speakResult(correct: _correctAnswers, total: _tasks.length);
  }

  // ── Antwort-Logik ─────────────────────────────────────────────────────────

  Future<void> _checkAnswer(String selected) async {
    if (_showFeedback) return;

    final task = _tasks[_currentIndex];
    final correct = selected == task.correctAnswer;

    setState(() {
      _showFeedback = true;
      _wasCorrect = correct;
      _feedbackText = correct ? task.feedbackCorrect : task.feedbackWrong;
      if (correct) _correctAnswers++;
      _stepResults[_currentIndex] = correct;
    });

    if (correct) {
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
              .addXP(userId: user.uid, childId: child.id, xpToAdd: 3);
        } catch (_) {}
      }
    } else {
      HapticFeedback.heavyImpact();
      _shakeController.forward().then((_) => _shakeController.reset());
    }

    _speakFeedback(_feedbackText);
    _feedbackController.forward().then((_) => _feedbackController.reverse());

    if (correct) {
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
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      setState(() => _showRetryChoice = true);
    }
  }

  void _advanceToNext() {
    setState(() {
      _showFeedback = false;
      _showRetryChoice = false;
      _orderTaps = [];
      _sliderValue = 0;
      _sliderMoved = false;
      _drawStrokes = [];
      _currentStroke = [];
      _isEvaluating = false;
      _drawAttempts = 0;
    });
    if (_currentIndex < _tasks.length - 1) {
      setState(() => _currentIndex++);
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

  void _retryCurrentQuestion() {
    setState(() {
      _showFeedback = false;
      _showRetryChoice = false;
      _orderTaps = [];
      _stepResults[_currentIndex] = null;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _speakCurrentQuestion();
    });
  }

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
      isPerfect: _correctAnswers == _tasks.length,
      timeTracker: _timeTracker,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_tasks.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isFinished) return _buildFinishScreen();

    if (_showTreasureChest) {
      return Scaffold(
        body: TreasureChestOverlay(
          earnedStars: _correctAnswers * 3,
          isPerfect: _correctAnswers == _tasks.length,
          onDismiss: () {
            setState(() {
              _showTreasureChest = false;
              _isFinished = true;
            });
            _finishQuiz();
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

    final task = _tasks[_currentIndex];

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
                  Expanded(child: _buildTaskArea(task)),
                ],
              ),

              // Feedback Overlay
              if (_showFeedback || _showRetryChoice) _buildFeedbackOverlay(),

              // Konfetti
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
                    Color(0xFFFFD700),
                    Color(0xFFFFA500),
                    Color(0xFFFF6B6B),
                    Color(0xFF4ECDC4),
                    Color(0xFFFFE66D),
                    Color(0xFFFF69B4),
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

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final child = ref.watch(activeChildProvider);
    final ttsState = ref.watch(ttsControllerProvider);

    // Schwierigkeitsstufe aus erstem Task (alle haben dieselbe Stufe)
    final stage = _tasks.isNotEmpty ? _tasks.first.difficultyLevel : 1;
    final stageEmoji = MathTaskEngine.stageEmoji(stage);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  ref.read(ttsControllerProvider.notifier).stop();
                  Navigator.pop(context);
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
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
              Expanded(
                child: AvatarProgressBar(
                  totalSteps: _tasks.length,
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
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _speakCurrentQuestion();
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
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
          // Schwierigkeits-Badge
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(stageEmoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 5),
                    Text(
                      'Level ${child?.level ?? 1} · ${MathTaskEngine.stageName(stage)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // ── Aufgaben-Bereich ──────────────────────────────────────────────────────

  Widget _buildTaskArea(MathTask task) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 8),

                // Fragen-Karte mit Shake-Animation
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) {
                    final offset = sin(_shakeAnim.value * pi * 3) * 8;
                    return Transform.translate(
                      offset: Offset(_wasCorrect ? 0 : offset, 0),
                      child: child,
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _buildQuestionWidget(task),
                  ),
                ),

                const SizedBox(height: 20),

                // Antwort-Bereich
                _buildAnswerArea(task),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Frage-Widget je nach Typ ──────────────────────────────────────────────

  Widget _buildQuestionWidget(MathTask task) {
    switch (task.type) {
      case MathTaskType.multipleChoice:
      case MathTaskType.fillBlank:
        return _buildFormulaQuestion(task);

      case MathTaskType.comparison:
        return _buildComparisonQuestion(task);

      case MathTaskType.countDots:
        return _buildCountDotsQuestion(task);

      case MathTaskType.numberOrder:
        return _buildOrderQuestion(task);

      case MathTaskType.numberLine:
        return _buildNumberLineQuestion(task);

      case MathTaskType.balanceScale:
        return _buildBalanceScaleQuestion(task);

      case MathTaskType.drawAnswer:
        return _buildDrawAnswerQuestion(task);

      case MathTaskType.missingNumber:
        return _buildMissingNumberQuestion(task);

      case MathTaskType.wordProblem:
        return _buildWordProblemQuestion(task);
    }
  }

  /// „4 + 3 = ?" und „4 + [?] = 7"
  Widget _buildFormulaQuestion(MathTask task) {
    return Column(
      children: [
        Text(
          task.type == MathTaskType.fillBlank ? '🧩' : '🔢',
          style: const TextStyle(fontSize: 40),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: _bounceAnim.value, child: child),
          child: _FormulaText(
            text: task.questionText,
            accentColor: widget.subjectColors.first,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          task.type == MathTaskType.fillBlank
              ? 'Welche Zahl fehlt?'
              : 'Was ist das Ergebnis?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// „5 __ 8" → < = >
  Widget _buildComparisonQuestion(MathTask task) {
    return Column(
      children: [
        const Text('⚖️', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumberBubble(
              number: task.compareLeft!,
              color: const Color(0xFF7C4DFF),
            ),
            const SizedBox(width: 16),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: const Center(
                child: Text(
                  '?',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            _NumberBubble(
              number: task.compareRight!,
              color: const Color(0xFF00897B),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Welches Zeichen passt?',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Emoji-Punkte zählen
  Widget _buildCountDotsQuestion(MathTask task) {
    final count = task.countAmount ?? 1;
    final raw = task.countEmoji ?? '🍎';

    // MIXED-Format: "MIXED:emoji1:n1:emoji2:n2"
    // Zeigt zwei verschiedene Emoji-Gruppen die zusammen gezählt werden sollen
    final isMixed = raw.startsWith('MIXED:');

    return Column(
      children: [
        Text(
          isMixed ? 'Wie viele sind es zusammen?' : task.questionText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 16),
        if (isMixed) ...[
          // MIXED: zwei Gruppen mit Pluszeichen dazwischen
          Builder(
            builder: (context) {
              final parts = raw.split(':');
              final e1 = parts.length > 1 ? parts[1] : '🍎';
              final n1 = parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1;
              final e2 = parts.length > 3 ? parts[3] : '🍌';
              final n2 = parts.length > 4 ? int.tryParse(parts[4]) ?? 1 : 1;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: List.generate(
                      n1,
                      (_) => Text(e1, style: const TextStyle(fontSize: 30)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '+',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: List.generate(
                      n2,
                      (_) => Text(e2, style: const TextStyle(fontSize: 30)),
                    ),
                  ),
                ],
              );
            },
          ),
        ] else ...[
          // Normal: eine Emoji-Sorte
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: List.generate(
              count,
              (_) => Text(raw, style: const TextStyle(fontSize: 32)),
            ),
          ),
        ],
      ],
    );
  }

  /// Zahlen sortieren
  Widget _buildOrderQuestion(MathTask task) {
    return Column(
      children: [
        const Text('🔢', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(
          task.questionText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 12),
        // Tippe-Fortschritt anzeigen
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(task.orderNumbers!.length, (i) {
            final hasValue = i < _orderTaps.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: hasValue
                    ? widget.subjectColors.first.withValues(alpha: 0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasValue
                      ? widget.subjectColors.first
                      : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  hasValue ? _orderTaps[i] : '',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: widget.subjectColors.first,
                  ),
                ),
              ),
            );
          }),
        ),
        if (_orderTaps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              onTap: () => setState(() => _orderTaps = []),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    'Nochmal',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Antwort-Bereich je nach Typ ───────────────────────────────────────────

  Widget _buildAnswerArea(MathTask task) {
    switch (task.type) {
      case MathTaskType.multipleChoice:
      case MathTaskType.fillBlank:
      case MathTaskType.countDots:
        return _buildFourButtons(task);

      case MathTaskType.comparison:
        return _buildComparisonButtons(task);

      case MathTaskType.numberOrder:
        return _buildOrderButtons(task);

      case MathTaskType.numberLine:
        return _buildSliderAnswer(task); // Slider

      case MathTaskType.balanceScale:
        return _buildFourButtons(task); // Waage → 4 Optionen antippen

      case MathTaskType.drawAnswer:
        return _buildDrawCanvas(task);

      case MathTaskType.missingNumber:
        return _buildFourButtons(task);

      case MathTaskType.wordProblem:
        return _buildFourButtons(task);
    }
  }

  /// 4 große Antwort-Buttons (2×2)
  Widget _buildFourButtons(MathTask task) {
    final enabled = !_showFeedback;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: task.options
          .map(
            (opt) => _MathAnswerButton(
              label: opt,
              colors: widget.subjectColors,
              enabled: enabled,
              onTap: () => _checkAnswer(opt),
            ),
          )
          .toList(),
    );
  }

  /// 3 große Buttons für < = >
  Widget _buildComparisonButtons(MathTask task) {
    final enabled = !_showFeedback;
    return Row(
      children: task.options
          .map(
            (opt) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _MathAnswerButton(
                  label: opt,
                  colors: widget.subjectColors,
                  enabled: enabled,
                  fontSize: 36,
                  onTap: () => _checkAnswer(opt),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  /// Buttons zum Antippen in Reihenfolge (numberOrder)
  Widget _buildOrderButtons(MathTask task) {
    final enabled = !_showFeedback;
    return Row(
      children: task.options
          .map(
            (opt) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _MathAnswerButton(
                  label: opt,
                  colors: widget.subjectColors,
                  enabled: enabled && !_orderTaps.contains(opt),
                  faded: _orderTaps.contains(opt),
                  onTap: () {
                    if (_orderTaps.contains(opt)) return;
                    final newTaps = [..._orderTaps, opt];
                    setState(() => _orderTaps = newTaps);
                    if (newTaps.length == task.orderNumbers!.length) {
                      _checkAnswer(newTaps.join(','));
                    }
                  },
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ── Zahlenstrahl ──────────────────────────────────────────────────────────

  // ── Waage ─────────────────────────────────────────────────────────────────

  Widget _buildBalanceScaleQuestion(MathTask task) {
    final left = task.scaleLeft ?? 0;
    final right = task.scaleRight ?? 0;
    final op = task.scaleOp ?? '+';

    return Column(
      children: [
        const SizedBox(height: 4),
        Text(
          op == '+' ? '$left + ? = $right' : '$left - ? = $right',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1A1A2E),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 16),
        // Animierte Waage
        _BalanceScaleWidget(
          leftValue: left,
          rightValue: right,
          color: widget.subjectColors.first,
        ),
        const SizedBox(height: 8),
        Text(
          'Was fehlt auf der Waage?',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Missing Number: Zahlenfolge mit Lücke ────────────────────────────────

  Widget _buildMissingNumberQuestion(MathTask task) {
    final seq = task.sequence ?? [];
    final blankIdx = task.blankIndex ?? 2;

    return Column(
      children: [
        const Text('🔍', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        const Text(
          'Welche Zahl fehlt?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 20),
        // Zahlenfolge als Reihe von Bubbles
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: seq.asMap().entries.map((e) {
            final isBlank = e.key == blankIdx;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: isBlank
                  ? Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: widget.subjectColors.first.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: widget.subjectColors.first,
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: widget.subjectColors.first.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          '${e.value}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                    ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Pfeil-Hinweis: Muster erkennen
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.trending_up_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              seq.length >= 2 ? 'Schritte: +${seq[1] - seq[0]}' : '',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Word Problem: Emoji-Textaufgabe ──────────────────────────────────────

  Widget _buildWordProblemQuestion(MathTask task) {
    final emoji = task.wpEmoji ?? '🍎';
    final left = task.wpLeft ?? 0;
    final right = task.wpRight ?? 0;
    final op = task.wpOp ?? '+';
    final isAddition = op == '+';

    return Column(
      children: [
        const SizedBox(height: 4),
        Text(
          isAddition
              ? 'Wie viele ${emoji}s sind es zusammen?'
              : 'Wie viele ${emoji}s bleiben übrig?',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 16),
        // Linke Gruppe
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 3,
          runSpacing: 3,
          children: List.generate(
            left,
            (_) => Text(emoji, style: const TextStyle(fontSize: 28)),
          ),
        ),
        // Operator
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            isAddition ? '➕' : '➖',
            style: const TextStyle(fontSize: 32),
          ),
        ),
        // Rechte Gruppe
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 3,
          runSpacing: 3,
          children: List.generate(
            right,
            (_) => Text(
              emoji,
              style: TextStyle(
                fontSize: 28,
                // Subtraktions-Gruppe etwas ausgeblendet
                color: isAddition ? null : const Color(0xFFAAAAAA),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '= ?',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: widget.subjectColors.first,
          ),
        ),
      ],
    );
  }

  // ── Zahlenstrahl (Slider) Frage-Widget ───────────────────────────────────

  Widget _buildNumberLineQuestion(MathTask task) {
    final min = task.lineMin ?? 0;
    final max = task.lineMax ?? 10;
    return Column(
      children: [
        const Text('📏', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(
          'Zeige die ${task.lineTarget ?? "?"}!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 16),
        // Zahlenstrahl nur zur Orientierung (nicht interaktiv)
        _NumberLineWidget(
          min: min,
          max: max,
          markerValue: _sliderMoved ? _sliderValue.round() : null,
          color: widget.subjectColors.first,
        ),
        const SizedBox(height: 4),
        Text(
          _sliderMoved
              ? 'Du zeigst auf: ${_sliderValue.round()}'
              : 'Schiebe den Regler!',
          style: TextStyle(
            fontSize: 14,
            color: _sliderMoved
                ? widget.subjectColors.first
                : Colors.grey.shade500,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Slider-Antwort für Zahlenstrahl ──────────────────────────────────────

  Widget _buildSliderAnswer(MathTask task) {
    final min = (task.lineMin ?? 0).toDouble();
    final max = (task.lineMax ?? 10).toDouble();
    if (!_sliderMoved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sliderValue = min);
      });
    }

    return Column(
      children: [
        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            // Spur: weiß aktiv, halbtransparent inaktiv → gut sichtbar auf
            // jedem farbigen Hintergrund
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.35),
            // Thumb: weiß mit farbigem Schatten → klar vom Hintergrund trennbar
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.25),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 22),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 36),
            trackHeight: 10,
          ),
          child: Slider(
            value: _sliderValue.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            onChanged: _showFeedback
                ? null
                : (v) => setState(() {
                    _sliderValue = v;
                    _sliderMoved = true;
                  }),
          ),
        ),
        const SizedBox(height: 8),
        // Bestätigen-Button
        GestureDetector(
          onTap: _sliderMoved && !_showFeedback
              ? () => _checkAnswer('${_sliderValue.round()}')
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: _sliderMoved
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _sliderMoved
                    ? widget.subjectColors.first
                    : Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: _sliderMoved
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                _sliderMoved
                    ? '✓ Das ist die ${_sliderValue.round()}!'
                    : 'Erst schieben...',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _sliderMoved
                      ? widget.subjectColors.first
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Draw Answer: Aufgabe + Zeichenfläche ──────────────────────────────────

  Widget _buildDrawAnswerQuestion(MathTask task) {
    return Column(
      children: [
        const Text('✏️', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: _bounceAnim.value, child: child),
          child: Text(
            task.questionText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A2E),
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Male die Antwort!',
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_drawAttempts > 0 && _drawAttempts < _maxDrawAttempts)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Versuch ${_drawAttempts + 1} von $_maxDrawAttempts',
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // ── Zeichenfläche + Prüfen-Button ─────────────────────────────────────────

  Widget _buildDrawCanvas(MathTask task) {
    return Column(
      children: [
        // Zeichenfläche
        RepaintBoundary(
          key: _canvasKey,
          child: GestureDetector(
            onPanStart: _showFeedback || _isEvaluating
                ? null
                : (d) => setState(() {
                    _currentStroke = [d.localPosition];
                  }),
            onPanUpdate: _showFeedback || _isEvaluating
                ? null
                : (d) => setState(() => _currentStroke.add(d.localPosition)),
            onPanEnd: _showFeedback || _isEvaluating
                ? null
                : (d) => setState(() {
                    _drawStrokes.add([..._currentStroke, null]);
                    _currentStroke = [];
                  }),
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: widget.subjectColors.first.withValues(alpha: 0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    // Mallinien
                    CustomPaint(
                      painter: _DrawingPainter(
                        strokes: _drawStrokes,
                        currentStroke: _currentStroke,
                        color: const Color(0xFF1A1A2E),
                      ),
                      child: const SizedBox.expand(),
                    ),
                    // Lade-Overlay
                    if (_isEvaluating)
                      Container(
                        color: Colors.white.withValues(alpha: 0.8),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: widget.subjectColors.first,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Ich schaue nach...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: widget.subjectColors.first,
                                ),
                              ),
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
        const SizedBox(height: 12),
        // Buttons: Löschen + Prüfen
        Row(
          children: [
            // Löschen
            GestureDetector(
              onTap: _isEvaluating || _showFeedback
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _drawStrokes = [];
                        _currentStroke = [];
                      });
                    },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFF888888),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Prüfen
            Expanded(
              child: GestureDetector(
                onTap:
                    (_drawStrokes.isEmpty && _currentStroke.isEmpty) ||
                        _isEvaluating ||
                        _showFeedback
                    ? null
                    : () => _submitDrawing(task),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 56,
                  decoration: BoxDecoration(
                    color:
                        (_drawStrokes.isNotEmpty || _currentStroke.isNotEmpty)
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          (_drawStrokes.isNotEmpty || _currentStroke.isNotEmpty)
                          ? widget.subjectColors.first
                          : Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: (_drawStrokes.isNotEmpty)
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '✓ Prüfen',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color:
                            (_drawStrokes.isNotEmpty ||
                                _currentStroke.isNotEmpty)
                            ? widget.subjectColors.first
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Vertex AI Erkennung ───────────────────────────────────────────────────

  Future<void> _submitDrawing(MathTask task) async {
    if (_isEvaluating) return;
    HapticFeedback.mediumImpact();
    setState(() => _isEvaluating = true);

    try {
      final imageBytes = await _captureCanvas();
      if (imageBytes == null || _aiModel == null) {
        // Fallback: als richtig werten
        setState(() => _isEvaluating = false);
        await _checkAnswer(task.correctAnswer);
        return;
      }

      final expected = task.correctAnswer;
      final prompt =
          'This is a handwritten number drawn by a young child (age 6-8). '
          'Does this drawing clearly show the digit "$expected"? '
          'STRICT RULES: '
          '1. Orientation must be correct — a mirrored or reversed "$expected" is WRONG. '
          '2. A "3" written backwards is WRONG. A "2" as mirror image is WRONG. '
          '3. "6" has the loop at the BOTTOM, "9" has the loop at the TOP — do not confuse them. '
          '4. The digit must be recognizable, but allow for typical child handwriting wobble. '
          '5. If the canvas looks empty or has only random scribbles, answer "no". '
          'Answer with ONLY the JSON: {"correct": true} or {"correct": false, "recognized": "<what you see>"}';

      final response = await _aiModel!
          .generateContent([
            Content.multi([
              TextPart(prompt),
              InlineDataPart('image/png', imageBytes),
            ]),
          ])
          .timeout(const Duration(seconds: 12));

      setState(() => _isEvaluating = false);

      final raw = response.text?.trim() ?? '{"correct": false}';
      bool isCorrect = false;
      String recognized = '?';
      try {
        // Strip markdown fences if present
        final json = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final parsed = jsonDecode(json) as Map<String, dynamic>;
        isCorrect = parsed['correct'] == true;
        recognized = parsed['recognized']?.toString() ?? expected;
      } catch (_) {
        // Fallback: einfaches yes/no
        isCorrect = raw.toLowerCase().contains('true');
      }

      if (isCorrect) {
        await _checkAnswer(expected); // korrekte Antwort
      } else {
        _drawAttempts++;
        if (_drawAttempts >= _maxDrawAttempts) {
          // Max Versuche → als falsch werten
          await _checkAnswer('__WRONG__');
        } else {
          // Nochmal versuchen
          HapticFeedback.heavyImpact();
          final msg = recognized != '?' && recognized != expected
              ? 'Das sieht aus wie eine $recognized — versuch nochmal!'
              : 'Ich kann die Zahl nicht lesen — nochmal!';
          setState(() {
            _drawStrokes = [];
            _currentStroke = [];
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  msg,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                backgroundColor: Colors.orange.shade600,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('MathQuiz: Draw evaluation error: $e');
      setState(() => _isEvaluating = false);
      // Bei Fehler positiv werten
      await _checkAnswer(task.correctAnswer);
    }
  }

  Future<Uint8List?> _captureCanvas() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('MathQuiz: canvas capture error: $e');
      return null;
    }
  }

  // ── Feedback Overlay ──────────────────────────────────────────────────────

  Widget _buildFeedbackOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _showRetryChoice ? null : () {},
        child: AnimatedOpacity(
          opacity: (_showFeedback || _showRetryChoice) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            decoration: BoxDecoration(
              color: (_wasCorrect ? Colors.green.shade400 : Colors.red.shade400)
                  .withValues(alpha: 0.92),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _feedbackController,
                    builder: (_, __) {
                      final scale =
                          1.0 + sin(_feedbackController.value * pi) * 0.3;
                      return Transform.scale(
                        scale: scale,
                        child: Text(
                          _wasCorrect ? '✅' : '❌',
                          style: const TextStyle(fontSize: 72),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      _feedbackText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  if (_showRetryChoice) ...[
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RetryButton(
                          emoji: '🔄',
                          label: 'Nochmal',
                          onTap: _retryCurrentQuestion,
                        ),
                        const SizedBox(width: 16),
                        _RetryButton(
                          emoji: '➡️',
                          label: 'Weiter',
                          onTap: _advanceToNext,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Finish Screen ─────────────────────────────────────────────────────────

  Widget _buildFinishScreen() {
    final allCorrect = _correctAnswers == _tasks.length;
    final earnedXP = _correctAnswers * 3;
    final showConfetti = _correctAnswers >= 4;

    // Falsch beantwortete Aufgaben sammeln
    final wrongTasks = <MathTask>[];
    for (int i = 0; i < _tasks.length; i++) {
      if (_stepResults[i] == false) wrongTasks.add(_tasks[i]);
    }

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
              SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const SizedBox(height: 16),

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
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Sterne
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _tasks.length,
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

                          // XP
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
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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

                    // Falsche Aufgaben anzeigen
                    if (wrongTasks.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🔁 Diese Aufgaben nochmal üben:',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...wrongTasks.map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Text(
                                      '❌',
                                      style: TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        t.type == MathTaskType.numberOrder
                                            ? '${t.questionText} (${t.orderNumbers!.map((n) => '$n').join(', ')})'
                                            : t.questionText,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '= ${t.correctAnswer}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

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
                              color: Colors.black.withValues(alpha: 0.18),
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
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // Konfetti
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

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

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
}

// ============================================================================
// HILFWIDGETS
// ============================================================================

/// Große Zahl in einem bunten Bubble (für Vergleichsfragen)
class _NumberBubble extends StatelessWidget {
  final int number;
  final Color color;

  const _NumberBubble({required this.number, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Großer Antwort-Button
class _MathAnswerButton extends StatefulWidget {
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool enabled;
  final bool faded;
  final double fontSize;

  const _MathAnswerButton({
    required this.label,
    required this.colors,
    required this.onTap,
    this.enabled = true,
    this.faded = false,
    this.fontSize = 28,
  });

  @override
  State<_MathAnswerButton> createState() => _MathAnswerButtonState();
}

class _MathAnswerButtonState extends State<_MathAnswerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => _ctrl.forward() : null,
      onTapUp: widget.enabled
          ? (_) {
              _ctrl.reverse();
              HapticFeedback.selectionClick();
              widget.onTap();
            }
          : null,
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedOpacity(
          opacity: widget.faded ? 0.35 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: widget.faded
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: widget.faded
                  ? null
                  : Border.all(
                      color: widget.colors.first.withValues(alpha: 0.3),
                      width: 2,
                    ),
              boxShadow: widget.faded
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w900,
                  color: widget.faded
                      ? Colors.white.withValues(alpha: 0.5)
                      : widget.colors.first,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retry-Button für das Feedback-Overlay
class _RetryButton extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _RetryButton({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ZAHLENSTRAHL WIDGET
// ============================================================================

class _NumberLineWidget extends StatelessWidget {
  final int min;
  final int max;
  final Color color;
  final int? markerValue;

  const _NumberLineWidget({
    required this.min,
    required this.max,
    required this.color,
    this.markerValue,
  });

  @override
  Widget build(BuildContext context) {
    // Zeige nur jeden 2. oder 5. Tick bei großem Bereich
    final showEvery = max > 20
        ? 10
        : max > 10
        ? 2
        : 1;

    return SizedBox(
      height: 72,
      child: CustomPaint(
        painter: _NumberLinePainter(
          min: min,
          max: max,
          color: color,
          showEvery: showEvery,
          markerValue: markerValue,
        ),
        size: const Size(double.infinity, 72),
      ),
    );
  }
}

class _NumberLinePainter extends CustomPainter {
  final int min;
  final int max;
  final Color color;
  final int showEvery;
  final int? markerValue;

  _NumberLinePainter({
    required this.min,
    required this.max,
    required this.color,
    required this.showEvery,
    this.markerValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final tickPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    const paddingX = 20.0;
    final lineY = size.height * 0.45;
    const lineStart = paddingX;
    final lineEnd = size.width - paddingX;

    // Hauptlinie
    canvas.drawLine(
      Offset(lineStart, lineY),
      Offset(lineEnd, lineY),
      linePaint,
    );

    // Pfeilspitze rechts
    canvas.drawLine(
      Offset(lineEnd, lineY),
      Offset(lineEnd - 10, lineY - 8),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(lineEnd, lineY),
      Offset(lineEnd - 10, lineY + 8),
      arrowPaint,
    );

    final range = (max - min).toDouble();
    final usableWidth = lineEnd - lineStart;

    for (int i = min; i <= max; i++) {
      final x = lineStart + (i - min) / range * usableWidth;
      final isLabeled = i == min || i == max || i % showEvery == 0;
      final tickHeight = isLabeled ? 12.0 : 7.0;

      canvas.drawLine(
        Offset(x, lineY - tickHeight),
        Offset(x, lineY + tickHeight),
        tickPaint,
      );

      if (isLabeled) {
        textPainter.text = TextSpan(
          text: '$i',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, lineY + tickHeight + 3),
        );
      }
    }

    // Marker-Dreieck für den Slider-Wert
    if (markerValue != null) {
      final mx = lineStart + (markerValue! - min) / range * usableWidth;
      final markerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(mx, lineY - 22)
        ..lineTo(mx - 10, lineY - 36)
        ..lineTo(mx + 10, lineY - 36)
        ..close();
      canvas.drawPath(path, markerPaint);
      textPainter.text = TextSpan(
        text: '$markerValue',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(mx - textPainter.width / 2, lineY - 34));
    }
  }

  @override
  bool shouldRepaint(covariant _NumberLinePainter old) =>
      old.markerValue != markerValue;
}

// ============================================================================
// WAAGE WIDGET
// ============================================================================

class _BalanceScaleWidget extends StatefulWidget {
  final int leftValue;
  final int rightValue;
  final Color color;

  const _BalanceScaleWidget({
    required this.leftValue,
    required this.rightValue,
    required this.color,
  });

  @override
  State<_BalanceScaleWidget> createState() => _BalanceScaleWidgetState();
}

class _BalanceScaleWidgetState extends State<_BalanceScaleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _tiltController;
  late Animation<double> _tiltAnim;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Die Waage kippt zur schwereren Seite (links ist immer der größere Wert)
    // Da wir zeigen wollen dass etwas fehlt, kippt sie leicht nach links
    _tiltAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _tiltController, curve: Curves.elasticOut),
    );
    _tiltController.forward();
  }

  @override
  void dispose() {
    _tiltController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tiltAnim,
      builder: (_, __) {
        // Neigungswinkel: links schwerer → linke Schale tiefer
        final tilt = _tiltAnim.value * 0.12; // ~7 Grad

        return SizedBox(
          height: 130,
          child: CustomPaint(
            painter: _BalanceScalePainter(
              leftValue: widget.leftValue,
              rightValue: widget.rightValue,
              tilt: tilt,
              color: widget.color,
            ),
            size: const Size(double.infinity, 130),
          ),
        );
      },
    );
  }
}

class _BalanceScalePainter extends CustomPainter {
  final int leftValue;
  final int rightValue;
  final double tilt;
  final Color color;

  _BalanceScalePainter({
    required this.leftValue,
    required this.rightValue,
    required this.tilt,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final poleTop = size.height * 0.08;
    final poleBottom = size.height * 0.65;
    final armY = poleTop + 10;
    final armHalf = size.width * 0.32;

    final polePaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final armPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final platePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final plateBorder = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Standfuß
    const baseW = 40.0;
    canvas.drawLine(
      Offset(cx - baseW, poleBottom),
      Offset(cx + baseW, poleBottom),
      polePaint..strokeWidth = 5,
    );
    // Mast
    canvas.drawLine(
      Offset(cx, poleBottom),
      Offset(cx, poleTop),
      polePaint..strokeWidth = 4,
    );
    // Drehpunkt-Kreis
    canvas.drawCircle(Offset(cx, armY), 6, Paint()..color = color);

    // Balken (geneigt)
    final leftEnd = Offset(cx - armHalf, armY + armHalf * tilt);
    final rightEnd = Offset(cx + armHalf, armY - armHalf * tilt);
    canvas.drawLine(leftEnd, rightEnd, armPaint..strokeWidth = 3);

    // Fäden
    const ropeLen = 28.0;
    final leftPlateCenter = Offset(leftEnd.dx, leftEnd.dy + ropeLen);
    final rightPlateCenter = Offset(rightEnd.dx, rightEnd.dy + ropeLen);

    canvas.drawLine(leftEnd, leftPlateCenter, armPaint..strokeWidth = 1.5);
    canvas.drawLine(rightEnd, rightPlateCenter, armPaint..strokeWidth = 1.5);

    // Schalen
    const plateW = 50.0;
    const plateH = 12.0;
    final leftPlateRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: leftPlateCenter, width: plateW, height: plateH),
      const Radius.circular(6),
    );
    final rightPlateRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: rightPlateCenter, width: plateW, height: plateH),
      const Radius.circular(6),
    );
    canvas.drawRRect(leftPlateRect, platePaint);
    canvas.drawRRect(leftPlateRect, plateBorder);
    canvas.drawRRect(rightPlateRect, platePaint);
    canvas.drawRRect(rightPlateRect, plateBorder);

    // Werte auf den Schalen
    final tp = TextPainter(textDirection: TextDirection.ltr);

    // Linke Schale: bekannter Wert
    tp.text = TextSpan(
      text: '$leftValue',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(
        leftPlateCenter.dx - tp.width / 2,
        leftPlateCenter.dy - plateH / 2 - tp.height - 2,
      ),
    );

    // Rechte Schale: gesuchter Wert (Fragezeichen)
    tp.text = TextSpan(
      text: '?',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: color.withValues(alpha: 0.5),
      ),
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(
        rightPlateCenter.dx - tp.width / 2,
        rightPlateCenter.dy - plateH / 2 - tp.height - 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _BalanceScalePainter old) => old.tilt != tilt;
}

// ============================================================================
// FORMEL-TEXT – rendert [?] als farbiges Kästchen, Rest als normalen Text
// ============================================================================

class _FormulaText extends StatelessWidget {
  final String text;
  final Color accentColor;

  const _FormulaText({required this.text, required this.accentColor});

  static const _style = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w900,
    color: Color(0xFF1A1A2E),
    height: 1.2,
    letterSpacing: 1.5, // etwas mehr Abstand → Minus klar von Box trennbar
  );

  @override
  Widget build(BuildContext context) {
    final parts = text.split('[?]');

    // Kein [?] → normaler Text (multipleChoice, comparison etc.)
    if (parts.length == 1) {
      return Text(text, textAlign: TextAlign.center, style: _style);
    }

    // Mit [?] → Wrap mit echtem Kästchen
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (parts[i].trim().isNotEmpty) Text(parts[i].trim(), style: _style),
          if (i < parts.length - 1)
            Container(
              width: 60,
              height: 52,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor, width: 3),
              ),
              child: Center(
                child: Text(
                  '?',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: accentColor.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ============================================================================
// DRAWING PAINTER – wie im TracingGame
// ============================================================================

class _DrawingPainter extends CustomPainter {
  final List<List<Offset?>> strokes;
  final List<Offset> currentStroke;
  final Color color;

  _DrawingPainter({
    required this.strokes,
    required this.currentStroke,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void drawStroke(List<Offset?> stroke) {
      final path = Path();
      bool moved = false;
      for (final point in stroke) {
        if (point == null) {
          moved = false;
          continue;
        }
        if (!moved) {
          path.moveTo(point.dx, point.dy);
          moved = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    for (final stroke in strokes) {
      drawStroke(stroke);
    }
    if (currentStroke.isNotEmpty) {
      drawStroke(currentStroke.map((o) => o as Offset?).toList());
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter old) => true;
}
