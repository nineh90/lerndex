import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:confetti/confetti.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/learning_time/learning_time_tracker.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/avatar_progress_bar.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/treasure_chest_overlay.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_finish_service.dart';
import 'color_shape_task_engine.dart';

// ============================================================================
// COLOR SHAPE QUIZ SCREEN – Klasse 1 & 2 (Farben & Formen)
//
// 5 Aufgabentypen, jeder kommt pro Runde genau einmal vor:
//   farbeNennen    – Welche Farbe siehst du?
//   formNennen     – Welche Form siehst du?
//   gleicheFarbe   – Was ist auch rot?
//   gleicheForm    – Was hat die gleiche Form?
//   farbMuster     – Farbmuster ergänzen
//   oddOneOutFarbe – Was ist nicht rot?
//   oddOneOutForm  – Was ist kein Kreis?
//   farbeZuordnen  – Welche Farbe hat dieses Objekt?
//   wieVieleEcken  – Wie viele Ecken?
//   formZeichnen   – Male einen Kreis (Vertex AI)
// ============================================================================

class ColorShapeQuizScreen extends ConsumerStatefulWidget {
  final int grade;
  final List<Color> subjectColors;

  const ColorShapeQuizScreen({
    super.key,
    required this.grade,
    required this.subjectColors,
  });

  @override
  ConsumerState<ColorShapeQuizScreen> createState() =>
      _ColorShapeQuizScreenState();
}

class _ColorShapeQuizScreenState extends ConsumerState<ColorShapeQuizScreen>
    with TickerProviderStateMixin {
  static const int _questionCount = 5;

  List<ColorShapeTask> _tasks = [];
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

  // Für formZeichnen
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

  void _generateTasks() {
    final child = ref.read(activeChildProvider);
    final engine = ColorShapeTaskEngine(
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

  Future<void> _initAI() async {
    try {
      _aiModel = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.0-flash',
        generationConfig: GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 30,
        ),
      );
    } catch (e) {
      debugPrint('ColorShapeQuiz: AI init failed: $e');
    }
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

  String _buildTtsText(ColorShapeTask task) {
    switch (task.type) {
      case ColorShapeTaskType.farbMuster:
      case ColorShapeTaskType.formMuster:
        final seq = task.sequence ?? [];
        return '${task.questionText.replaceAll('?', '')} – was kommt als nächstes?';
      case ColorShapeTaskType.farbeZuordnen:
        return task.questionText; // z.B. "Welche Farbe hat das?"
      case ColorShapeTaskType.wieVieleEcken:
        return task.questionText;
      case ColorShapeTaskType.formZeichnen:
        return task.questionText;
      default:
        return task.questionText;
    }
  }

  void _speakFeedback(String text) {
    if (!_ttsEnabled) return;
    // Emojis aus Feedback-Text entfernen für TTS
    final clean = text
        .replaceAll(RegExp(r'[^\x00-\x7F\u00C0-\u017F\s]'), '')
        .trim();
    ref.read(ttsControllerProvider.notifier).speakFeedback(clean);
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
        int w = 0;
        while (w < 4000 &&
            mounted &&
            ref.read(ttsControllerProvider).isSpeaking) {
          await Future.delayed(const Duration(milliseconds: 100));
          w += 100;
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
      _drawStrokes = [];
      _currentStroke = [];
      _isEvaluating = false;
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

  // ── Vertex AI Form-Erkennung ──────────────────────────────────────────────

  Future<void> _submitDrawing(ColorShapeTask task) async {
    if (_isEvaluating) return;
    HapticFeedback.mediumImpact();
    setState(() => _isEvaluating = true);

    try {
      final imageBytes = await _captureCanvas();
      if (imageBytes == null || _aiModel == null) {
        setState(() => _isEvaluating = false);
        await _checkAnswer(task.correctAnswer);
        return;
      }

      final shape = task.correctAnswer;
      final shapeHints = {
        'Kreis':
            'A Kreis (circle) is perfectly round with no corners or edges. A squiggly blob is WRONG.',
        'Dreieck':
            'A Dreieck (triangle) has exactly 3 straight sides and 3 corners.',
        'Quadrat':
            'A Quadrat (square) has 4 equal straight sides and 4 corners.',
        'Rechteck':
            'A Rechteck (rectangle) has 4 straight sides, two pairs of equal length.',
        'Stern': 'A Stern (star) has 5 points.',
        'Raute': 'A Raute (diamond) has 4 equal sides, pointed top and bottom.',
      };
      final hint = shapeHints[shape] ?? '';

      final prompt =
          'This is a drawing by a young child (age 6-8). '
          'Does this drawing show a "$shape"? '
          'RULES: $hint '
          'Allow for imperfect child drawing (wobbly lines, not perfectly round). '
          'If the canvas is mostly empty or just random scribbles, answer false. '
          'Answer ONLY with JSON: {"correct": true} or {"correct": false, "recognized": "<what you see>"}';

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
        final json = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final parsed = jsonDecode(json) as Map<String, dynamic>;
        isCorrect = parsed['correct'] == true;
        recognized = parsed['recognized']?.toString() ?? shape;
      } catch (_) {
        isCorrect = raw.toLowerCase().contains('true');
      }

      if (isCorrect) {
        await _checkAnswer(shape);
      } else {
        _drawAttempts++;
        if (_drawAttempts >= _maxDrawAttempts) {
          await _checkAnswer('__WRONG__');
        } else {
          HapticFeedback.heavyImpact();
          final msg = recognized != '?' && recognized != shape
              ? 'Das sieht aus wie $recognized – versuch nochmal!'
              : 'Ich erkenne keinen $shape – nochmal!';
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
      debugPrint('ColorShapeQuiz: Draw error: $e');
      setState(() => _isEvaluating = false);
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
      debugPrint('ColorShapeQuiz: capture error: $e');
      return null;
    }
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
              if (_showFeedback || _showRetryChoice) _buildFeedbackOverlay(),
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
    final stage = _tasks.isNotEmpty ? _tasks.first.difficultyLevel : 1;

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
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ColorShapeTaskEngine.stageEmoji(stage),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 5),
                Text(
                  'Level ${child?.level ?? 1} · ${ColorShapeTaskEngine.stageName(stage)}',
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
    );
  }

  // ── Task Area ─────────────────────────────────────────────────────────────

  Widget _buildTaskArea(ColorShapeTask task) {
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
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _buildQuestionWidget(task),
                  ),
                ),
                const SizedBox(height: 20),
                _buildAnswerArea(task),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Frage-Widgets ─────────────────────────────────────────────────────────

  Widget _buildQuestionWidget(ColorShapeTask task) {
    switch (task.type) {
      case ColorShapeTaskType.farbeNennen:
      case ColorShapeTaskType.formNennen:
      case ColorShapeTaskType.gleicheFarbe:
      case ColorShapeTaskType.gleicheForm:
      case ColorShapeTaskType.oddOneOutFarbe:
      case ColorShapeTaskType.oddOneOutForm:
      case ColorShapeTaskType.wieVieleEcken:
        return _buildSimpleQuestion(task);

      case ColorShapeTaskType.farbMuster:
      case ColorShapeTaskType.formMuster:
        return _buildMusterQuestion(task);

      case ColorShapeTaskType.farbeZuordnen:
        return _buildSimpleQuestion(task); // Emoji + Frage – kein Overflow

      case ColorShapeTaskType.formZeichnen:
        return _buildFormZeichnenQuestion(task);
    }
  }

  /// Standard-Aufgabe: großes Emoji + Frage-Text
  Widget _buildSimpleQuestion(ColorShapeTask task) {
    return Column(
      children: [
        if (task.questionEmoji != null)
          AnimatedBuilder(
            animation: _bounceAnim,
            builder: (_, child) =>
                Transform.scale(scale: _bounceAnim.value, child: child),
            child: Text(
              task.questionEmoji!,
              style: const TextStyle(fontSize: 80),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          task.questionText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  /// Muster-Aufgabe: Emoji-Reihe + ? am Ende
  Widget _buildMusterQuestion(ColorShapeTask task) {
    final seq = task.sequence ?? [];
    return Column(
      children: [
        Text(
          'Was kommt als nächstes?',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            ...seq.map((e) => Text(e, style: const TextStyle(fontSize: 36))),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.subjectColors.first.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.subjectColors.first,
                  width: 2.5,
                ),
              ),
              child: Center(
                child: Text(
                  '?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: widget.subjectColors.first.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Form zeichnen
  Widget _buildFormZeichnenQuestion(ColorShapeTask task) {
    return Column(
      children: [
        const Text('🖌️', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: _bounceAnim.value, child: child),
          child: Text(
            task.questionText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        if (task.questionEmoji != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              task.questionEmoji!,
              style: const TextStyle(fontSize: 48),
            ),
          ),
        if (_drawAttempts > 0 && _drawAttempts < _maxDrawAttempts)
          Padding(
            padding: const EdgeInsets.only(top: 8),
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

  // ── Antwort-Bereich ───────────────────────────────────────────────────────

  Widget _buildAnswerArea(ColorShapeTask task) {
    if (task.type == ColorShapeTaskType.formZeichnen) {
      return _buildDrawCanvas(task);
    }
    // Standard 4-Button-Antwort
    return _buildAnswerButtons(task);
  }

  Widget _buildAnswerButtons(ColorShapeTask task) {
    final enabled = !_showFeedback;
    // 2 Buttons nebeneinander wenn nur 2 Optionen, sonst 2×2
    if (task.options.length <= 2) {
      return Row(
        children: task.options
            .map(
              (opt) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _ColorShapeButton(
                    label: opt,
                    colors: widget.subjectColors,
                    enabled: enabled,
                    onTap: () => _checkAnswer(opt),
                  ),
                ),
              ),
            )
            .toList(),
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.0,
      children: task.options
          .map(
            (opt) => _ColorShapeButton(
              label: opt,
              colors: widget.subjectColors,
              enabled: enabled,
              onTap: () => _checkAnswer(opt),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDrawCanvas(ColorShapeTask task) {
    return Column(
      children: [
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
                  color: widget.subjectColors.first.withOpacity(0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _DrawingPainter(
                        strokes: _drawStrokes,
                        currentStroke: _currentStroke,
                        color: const Color(0xFF1A1A2E),
                      ),
                      child: const SizedBox.expand(),
                    ),
                    if (_isEvaluating)
                      Container(
                        color: Colors.white.withOpacity(0.8),
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
        Row(
          children: [
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
                        : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          (_drawStrokes.isNotEmpty || _currentStroke.isNotEmpty)
                          ? widget.subjectColors.first
                          : Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: _drawStrokes.isNotEmpty
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
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
                            : Colors.white.withOpacity(0.4),
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

  // ── Feedback Overlay ──────────────────────────────────────────────────────

  Widget _buildFeedbackOverlay() {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: (_showFeedback || _showRetryChoice) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: (_wasCorrect ? Colors.green.shade400 : Colors.red.shade400)
                .withOpacity(0.92),
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
                      fontSize: 20,
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
                      _RetryBtn(
                        emoji: '🔄',
                        label: 'Nochmal',
                        onTap: _retryCurrentQuestion,
                      ),
                      const SizedBox(width: 16),
                      _RetryBtn(
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
    );
  }

  // ── Finish Screen ─────────────────────────────────────────────────────────

  Widget _buildFinishScreen() {
    final allCorrect = _correctAnswers == _tasks.length;
    final earnedXP = _correctAnswers * 3;
    final showConfetti = _correctAnswers >= 4;

    final wrongTasks = <ColorShapeTask>[];
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
                    if (wrongTasks.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
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
                                        t.questionText,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.25),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '→ ${t.correctAnswer}',
                                        style: const TextStyle(
                                          fontSize: 14,
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
                    const SizedBox(height: 20),
                  ],
                ),
              ),
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
// HELPER WIDGETS
// ============================================================================

/// Antwort-Button
class _ColorShapeButton extends StatefulWidget {
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool enabled;

  const _ColorShapeButton({
    required this.label,
    required this.colors,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_ColorShapeButton> createState() => _ColorShapeButtonState();
}

class _ColorShapeButtonState extends State<_ColorShapeButton>
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.colors.first.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: widget.colors.first,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retry-Button
class _RetryBtn extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _RetryBtn({
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
              color: Colors.black.withOpacity(0.2),
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

/// Drawing Painter
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

    for (final stroke in strokes) drawStroke(stroke);
    if (currentStroke.isNotEmpty) {
      drawStroke(currentStroke.map((o) => o as Offset?).toList());
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter old) => true;
}
