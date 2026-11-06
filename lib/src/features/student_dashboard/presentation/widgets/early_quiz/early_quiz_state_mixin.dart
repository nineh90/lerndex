import 'dart:convert';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/ai/ai_model.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/learning_time/learning_time_tracker.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';

import '../treasure_chest_overlay.dart';
import 'draw_canvas.dart';
import 'early_quiz_session.dart';
import 'early_quiz_widgets.dart';

// ============================================================================
// EARLY QUIZ STATE – gemeinsamer Ablauf der Quizze für Klasse 1–2
//
// Lernzeit, Sprachausgabe, Antwortprüfung, Weiter/Nochmal, Malprüfung,
// Schatzkiste und Abschluss stecken hier. Die Bildschirme liefern nur ihre
// Aufgaben (generateTasks) und die Frage-/Antwort-Widgets.
// ============================================================================

mixin EarlyQuizStateMixin<W extends ConsumerStatefulWidget, T extends EarlyTask>
    on ConsumerState<W>, TickerProvider {
  static const int questionCount = 5;
  static const int maxDrawAttempts = 3;

  // ── Von den Bildschirmen zu liefern ──────────────────────────────────────

  /// Fach für die Lernzeit-Statistik ("Zahlen", "Buchstaben", …).
  String get subject;

  /// Kürzel für Log-Ausgaben.
  String get logTag;

  List<Color> get subjectColors;

  List<T> generateTasks({required int level});

  /// Text, den die Sprachausgabe für die Aufgabe vorliest.
  String ttsTextFor(T task) => task.questionText;

  /// Text fürs Vorlesen des Feedbacks.
  String ttsFeedbackText(String text) => text;

  String stageName(int stage);
  String stageEmoji(int stage);

  Widget buildQuestionWidget(T task);
  Widget buildAnswerArea(T task);

  /// Bildschirm-eigene Eingaben zurücksetzen (Weiter/Nochmal).
  void resetTaskInput() {}

  /// Schriftgröße im Feedback-Overlay.
  double get feedbackFontSize => 22;

  WrongTaskStyle get wrongTaskStyle => const WrongTaskStyle();

  // ── Zustand ──────────────────────────────────────────────────────────────

  List<T> tasks = [];
  int currentIndex = 0;
  EarlyQuizScore score = EarlyQuizScore(0);
  bool isFinished = false;
  bool showFeedback = false;
  bool wasCorrect = false;
  bool showRetryChoice = false;
  String feedbackText = '';
  bool showTreasureChest = false;

  // Malaufgaben
  final DrawingController drawing = DrawingController();
  bool isEvaluating = false;
  int drawAttempts = 0;
  // Prüfung nicht erreichbar (offline, KI gestört) – ab 2 Mal „Weiter“
  int drawCheckFailures = 0;
  AiModel? _aiModel;

  // Animation
  late AnimationController feedbackController;
  late AnimationController bounceController;
  late Animation<double> bounceAnim;
  late AnimationController shakeController;
  late Animation<double> shakeAnim;

  // Konfetti
  late ConfettiController confettiController;
  late ConfettiController finishConfettiController;

  // Tracking
  LearningTimeTracker? _timeTracker;
  EarlyQuizFinish? _finish;
  String? _childId;
  late final TtsController tts;

  @override
  void initState() {
    super.initState();
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    _childId = child?.id;
    tts = ref.read(ttsControllerProvider.notifier);

    if (child != null && user != null) {
      _timeTracker = LearningTimeTracker(
        userId: user.ownerUid,
        childId: child.id,
        subject: subject,
      );
      _timeTracker!.startTracking();
      _finish = EarlyQuizFinish(
        userId: user.ownerUid,
        childId: child.id,
        timeTracker: _timeTracker,
      );
    }

    feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    bounceAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: bounceController, curve: Curves.elasticOut),
    );
    shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: shakeController, curve: Curves.elasticOut),
    );
    confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    finishConfettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );

    tasks = generateTasks(level: child?.level ?? 1);
    score = EarlyQuizScore(tasks.length);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) speakCurrentQuestion();
    });

    try {
      _aiModel = VertexAIService.drawingCheckModel(
        responseSchema: VertexAIService.drawingCheckSchema,
      );
    } catch (e) {
      debugPrint('$logTag: AI init failed: $e');
    }
  }

  @override
  void dispose() {
    feedbackController.dispose();
    bounceController.dispose();
    shakeController.dispose();
    confettiController.dispose();
    finishConfettiController.dispose();
    drawing.dispose();
    // Abbruch mitten im Quiz: XP und Lernzeit retten. Quiz fertig: der
    // Abschluss läuft ohne diesen Bildschirm zu Ende.
    _finish?.onDispose(pendingXP: score.earnedXP);
    tts.stop();
    super.dispose();
  }

  // ── Sprachausgabe ─────────────────────────────────────────────────────────

  bool get ttsEnabled {
    if (_childId == null) return false;
    return ref.read(ttsSettingsProvider(_childId!));
  }

  void speakCurrentQuestion() {
    if (!ttsEnabled || tasks.isEmpty) return;
    tts.speakQuestion(ttsTextFor(tasks[currentIndex]));
  }

  void speakFeedback(String text) {
    if (!ttsEnabled) return;
    tts.speakFeedback(ttsFeedbackText(text));
  }

  void speakResult() {
    if (!ttsEnabled) return;
    tts.speakResult(correct: score.correctCount, total: tasks.length);
  }

  /// Wartet (höchstens 4 s), bis die Sprachausgabe fertig ist.
  Future<void> _waitForSpeechEnd() async {
    if (!ttsEnabled || !ref.read(ttsControllerProvider).isSpeaking) return;
    try {
      await tts.stream
          .firstWhere((s) => !s.isSpeaking)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Timeout oder Controller weg – einfach weiter
    }
  }

  // ── Antwort-Logik ─────────────────────────────────────────────────────────

  Future<void> checkAnswer(String selected) async {
    if (showFeedback) return;
    final task = tasks[currentIndex];
    final correct = selected == task.correctAnswer;

    setState(() {
      showFeedback = true;
      wasCorrect = correct;
      feedbackText = correct ? task.feedbackCorrect : task.feedbackWrong;
      score.record(currentIndex, correct: correct);
    });

    if (correct) {
      HapticFeedback.lightImpact();
      bounceController.forward().then((_) => bounceController.reverse());
      confettiController.play();
    } else {
      HapticFeedback.heavyImpact();
      shakeController.forward().then((_) => shakeController.reset());
    }

    if (!mounted) return;
    speakFeedback(feedbackText);
    feedbackController.forward().then((_) => feedbackController.reverse());

    if (correct) {
      await Future.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
      await _waitForSpeechEnd();
      if (!mounted) return;
      setState(() => showFeedback = false);
      advanceToNext();
    } else {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      setState(() => showRetryChoice = true);
    }
  }

  void advanceToNext() {
    setState(() {
      showFeedback = false;
      showRetryChoice = false;
      resetTaskInput();
      drawing.clear();
      isEvaluating = false;
      drawAttempts = 0;
      drawCheckFailures = 0;
    });
    if (currentIndex < tasks.length - 1) {
      setState(() => currentIndex++);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) speakCurrentQuestion();
      });
    } else {
      // Abschluss sofort starten – nicht erst nach der Schatzkiste.
      _startFinish();
      if (score.earnsTreasure) {
        setState(() => showTreasureChest = true);
      } else {
        setState(() => isFinished = true);
        _presentFinish();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) speakResult();
        });
      }
    }
  }

  void retryCurrentQuestion() {
    setState(() {
      showFeedback = false;
      showRetryChoice = false;
      resetTaskInput();
      drawing.clear();
      isEvaluating = false;
      drawAttempts = 0;
      drawCheckFailures = 0;
      score.retry(currentIndex);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) speakCurrentQuestion();
    });
  }

  void _startFinish() {
    _timeTracker?.stopTracking();
    _finish?.start(ref, isPerfect: score.isPerfect, earnedXP: score.earnedXP);
  }

  /// Popups (Belohnung, Streak) erst, wenn der Abschluss-Bildschirm steht.
  void _presentFinish() => _finish?.present(() => mounted ? context : null);

  // ── Malaufgaben ───────────────────────────────────────────────────────────

  /// Schickt die Zeichnung an die KI. [prompt] beschreibt, was zu sehen sein
  /// soll; [wrongMessage] erzeugt den Hinweis bei nicht erkanntem Bild aus
  /// dem, was die KI erkannt hat.
  Future<void> submitDrawing({
    required String expected,
    required String prompt,
    required String Function(String recognized) wrongMessage,
  }) async {
    if (isEvaluating) return;
    HapticFeedback.mediumImpact();
    setState(() => isEvaluating = true);

    // null = nicht prüfbar (kein Modell/Bild, offline, Timeout, KI-Fehler,
    // ungültiges JSON) → weder richtig noch falsch werten.
    bool? isCorrect;
    String recognized = '';
    try {
      final imageBytes = await drawing.capturePng();
      if (imageBytes != null && _aiModel != null) {
        final response = await _aiModel!
            .generateContent([
              Content.multi([
                TextPart(prompt),
                InlineDataPart('image/png', imageBytes),
              ]),
            ])
            .timeout(const Duration(seconds: 12));

        // Strip markdown fences if present
        final json = (response.text ?? '')
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final parsed = jsonDecode(json) as Map<String, dynamic>;
        final correct = parsed['correct'];
        if (correct is bool) {
          isCorrect = correct;
          recognized = parsed['recognized']?.toString().trim() ?? '';
        }
      }
    } catch (e) {
      debugPrint('$logTag: Draw evaluation error: $e');
    }

    if (!mounted) return;
    setState(() => isEvaluating = false);

    if (isCorrect == null) {
      // Kein Versuch verbraucht, Zeichnung bleibt → Kind kann neu abschicken.
      // Klappt die Prüfung wiederholt nicht, darf es überspringen (Weiter).
      HapticFeedback.heavyImpact();
      setState(() => drawCheckFailures++);
      final msg = drawCheckFailures >= 2
          ? 'Ich kann gerade nicht nachschauen. Tippe auf Weiter!'
          : 'Ups, das hat gerade nicht geklappt. Versuch es gleich nochmal!';
      showDrawHint(msg);
      speakFeedback(msg);
      return;
    }

    if (isCorrect) {
      await checkAnswer(expected);
    } else {
      drawAttempts++;
      score.markFailedAttempt(currentIndex);
      if (drawAttempts >= maxDrawAttempts) {
        // Max Versuche → als falsch werten
        await checkAnswer('__WRONG__');
      } else {
        HapticFeedback.heavyImpact();
        setState(drawing.clear);
        showDrawHint(wrongMessage(recognized));
      }
    }
  }

  /// Malprüfung nicht erreichbar: Aufgabe ohne Wertung überspringen.
  void skipDrawTask() {
    score.skip(currentIndex);
    advanceToNext();
  }

  void showDrawHint(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.orange.shade600,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Zeichenfläche mit Prüfen/Löschen (und „Weiter“, wenn die KI ausfällt).
  Widget buildDrawCanvas({required VoidCallback onSubmit}) {
    return DrawCanvas(
      controller: drawing,
      accentColor: subjectColors.first,
      enabled: !showFeedback,
      isEvaluating: isEvaluating,
      onSubmit: onSubmit,
      onSkip: drawCheckFailures >= 2 ? skipDrawTask : null,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (isFinished) return _buildFinishScreen();
    if (showTreasureChest) {
      return Scaffold(
        body: TreasureChestOverlay(
          earnedStars: score.earnedXP,
          isPerfect: score.isPerfect,
          onDismiss: () {
            setState(() {
              showTreasureChest = false;
              isFinished = true;
            });
            _presentFinish();
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                speakResult();
                finishConfettiController.play();
              }
            });
          },
        ),
      );
    }

    final task = tasks[currentIndex];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [subjectColors.first, subjectColors.last],
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
              if (showFeedback || showRetryChoice)
                QuizFeedbackOverlay(
                  wasCorrect: wasCorrect,
                  text: feedbackText,
                  showRetryChoice: showRetryChoice,
                  animation: feedbackController,
                  onRetry: retryCurrentQuestion,
                  onNext: advanceToNext,
                  fontSize: feedbackFontSize,
                ),
              AnswerConfetti(controller: confettiController),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final child = ref.watch(activeChildProvider);
    final ttsState = ref.watch(ttsControllerProvider);
    // Schwierigkeitsstufe aus erstem Task (alle haben dieselbe Stufe)
    final stage = tasks.first.difficultyLevel;
    return EarlyQuizHeader(
      taskCount: tasks.length,
      currentIndex: currentIndex,
      stepResults: score.stepResults,
      avatarId: child?.selectedAvatar,
      childName: child?.name ?? '',
      level: child?.level ?? 1,
      subjectColor: subjectColors.first,
      stageEmoji: stageEmoji(stage),
      stageName: stageName(stage),
      isSpeaking: ttsState.isSpeaking,
      canSpeak: ttsState.isAvailable,
      onBack: () {
        tts.stop();
        Navigator.pop(context);
      },
      onSpeak: speakCurrentQuestion,
    );
  }

  Widget _buildTaskArea(T task) {
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
                  animation: shakeAnim,
                  builder: (_, child) {
                    final offset = sin(shakeAnim.value * pi * 3) * 8;
                    return Transform.translate(
                      offset: Offset(wasCorrect ? 0 : offset, 0),
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
                    child: buildQuestionWidget(task),
                  ),
                ),
                const SizedBox(height: 20),
                buildAnswerArea(task),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinishScreen() {
    return EarlyQuizFinishScreen(
      subjectColors: subjectColors,
      taskCount: tasks.length,
      correctCount: score.correctCount,
      earnedXP: score.earnedXP,
      isPerfect: score.isPerfect,
      showConfetti: score.earnsTreasure,
      wrongTasks: [
        for (int i = 0; i < tasks.length; i++)
          if (score.stepResults[i] == false)
            (tasks[i].questionText, tasks[i].correctAnswer),
      ],
      confettiController: finishConfettiController,
      wrongTaskStyle: wrongTaskStyle,
      onHome: () {
        tts.stop();
        Navigator.pop(context);
      },
    );
  }
}
