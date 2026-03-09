import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';

// ============================================================================
// TRACING GAME SCREEN – Klasse 1–2
//
// Spielablauf:
// 1. TTS spricht „Male den Buchstaben A" (oder eine Zahl)
// 2. Kind malt auf dem Canvas mit dem Finger
// 3. Canvas-Screenshot → base64 → Vertex AI (Gemini)
// 4. KI wertet aus: „Sieht das wie ein A aus?"
// 5. Feedback: ✅ Super gemalt! / 💪 Nochmal versuchen!
//
// DSGVO: Keine Persistierung des Bildes. Nur ephemere KI-Auswertung.
// Das Bild zeigt ausschließlich Strichlinien (keine Personendaten).
// ============================================================================

// ── Aufgaben-Pool ─────────────────────────────────────────────────────────────

class _TracingTask {
  final String character; // z.B. "A", "3"
  final String ttsPrompt; // Was TTS sagt
  final String displayHint; // Zeigt das Referenz-Zeichen grau im Hintergrund
  final bool isLetter;

  const _TracingTask({
    required this.character,
    required this.ttsPrompt,
    required this.displayHint,
    required this.isLetter,
  });
}

final _letterTasks = [
  const _TracingTask(
    character: 'A',
    ttsPrompt: 'Male den Buchstaben A',
    displayHint: 'A',
    isLetter: true,
  ),
  const _TracingTask(
    character: 'B',
    ttsPrompt: 'Male den Buchstaben B',
    displayHint: 'B',
    isLetter: true,
  ),
  const _TracingTask(
    character: 'M',
    ttsPrompt: 'Male den Buchstaben M',
    displayHint: 'M',
    isLetter: true,
  ),
  const _TracingTask(
    character: 'O',
    ttsPrompt: 'Male den Buchstaben O',
    displayHint: 'O',
    isLetter: true,
  ),
  const _TracingTask(
    character: 'S',
    ttsPrompt: 'Male den Buchstaben S',
    displayHint: 'S',
    isLetter: true,
  ),
  const _TracingTask(
    character: 'T',
    ttsPrompt: 'Male den Buchstaben T',
    displayHint: 'T',
    isLetter: true,
  ),
  const _TracingTask(
    character: 'L',
    ttsPrompt: 'Male den Buchstaben L',
    displayHint: 'L',
    isLetter: true,
  ),
  const _TracingTask(
    character: 'E',
    ttsPrompt: 'Male den Buchstaben E',
    displayHint: 'E',
    isLetter: true,
  ),
];

final _numberTasks = [
  const _TracingTask(
    character: '1',
    ttsPrompt: 'Male die Zahl 1',
    displayHint: '1',
    isLetter: false,
  ),
  const _TracingTask(
    character: '2',
    ttsPrompt: 'Male die Zahl 2',
    displayHint: '2',
    isLetter: false,
  ),
  const _TracingTask(
    character: '3',
    ttsPrompt: 'Male die Zahl 3',
    displayHint: '3',
    isLetter: false,
  ),
  const _TracingTask(
    character: '4',
    ttsPrompt: 'Male die Zahl 4',
    displayHint: '4',
    isLetter: false,
  ),
  const _TracingTask(
    character: '5',
    ttsPrompt: 'Male die Zahl 5',
    displayHint: '5',
    isLetter: false,
  ),
  const _TracingTask(
    character: '6',
    ttsPrompt: 'Male die Zahl 6',
    displayHint: '6',
    isLetter: false,
  ),
  const _TracingTask(
    character: '7',
    ttsPrompt: 'Male die Zahl 7',
    displayHint: '7',
    isLetter: false,
  ),
  const _TracingTask(
    character: '8',
    ttsPrompt: 'Male die Zahl 8',
    displayHint: '8',
    isLetter: false,
  ),
];

// ── Modus ─────────────────────────────────────────────────────────────────────

enum TracingMode { letters, numbers, mixed }

// ============================================================================
// MAIN SCREEN
// ============================================================================

class TracingGameScreen extends ConsumerStatefulWidget {
  final List<Color> subjectColors;
  final TracingMode mode;

  const TracingGameScreen({
    super.key,
    required this.subjectColors,
    this.mode = TracingMode.mixed,
  });

  @override
  ConsumerState<TracingGameScreen> createState() => _TracingGameScreenState();
}

class _TracingGameScreenState extends ConsumerState<TracingGameScreen>
    with TickerProviderStateMixin {
  late List<_TracingTask> _tasks;
  int _taskIndex = 0;
  int _correctCount = 0;
  int _totalAnswered = 0;

  // Canvas
  final _canvasKey = GlobalKey();
  final List<List<Offset?>> _strokes = [];
  List<Offset?> _currentStroke = [];

  // Status
  _TracingStatus _status = _TracingStatus.idle;
  String _feedbackText = '';
  String _feedbackEmoji = '';
  bool _showHint = true;

  // AI
  GenerativeModel? _aiModel;

  // Animationen
  late AnimationController _feedbackCtrl;
  late Animation<double> _feedbackScale;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  static const int _totalRounds = 5;

  @override
  void initState() {
    super.initState();
    _buildTaskList();

    _feedbackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _feedbackScale = CurvedAnimation(
      parent: _feedbackCtrl,
      curve: Curves.elasticOut,
    );

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);

    _initAI();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrentTask());
  }

  void _buildTaskList() {
    List<_TracingTask> pool;
    switch (widget.mode) {
      case TracingMode.letters:
        pool = [..._letterTasks];
        break;
      case TracingMode.numbers:
        pool = [..._numberTasks];
        break;
      case TracingMode.mixed:
        pool = [..._letterTasks, ..._numberTasks];
        break;
    }
    pool.shuffle(Random());
    _tasks = pool.take(_totalRounds).toList();
  }

  Future<void> _initAI() async {
    try {
      _aiModel = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.0-flash',
        generationConfig: GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 50,
        ),
      );
    } catch (e) {
      debugPrint('TracingGame: AI init failed: $e');
    }
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    _shakeCtrl.dispose();
    ref.read(ttsControllerProvider.notifier).stop();
    super.dispose();
  }

  _TracingTask get _currentTask => _tasks[_taskIndex];

  // ── TTS ────────────────────────────────────────────────────────────────────

  void _speakCurrentTask() {
    final child = ref.read(activeChildProvider);
    if (child == null) return;
    final ttsEnabled = ref.read(ttsSettingsProvider(child.id));
    if (ttsEnabled) {
      ref.read(ttsControllerProvider.notifier).speak(_currentTask.ttsPrompt);
    }
  }

  // ── Canvas ────────────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (_status != _TracingStatus.idle) return;
    setState(() {
      _currentStroke = [d.localPosition];
      _showHint = false;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_status != _TracingStatus.idle) return;
    setState(() => _currentStroke.add(d.localPosition));
  }

  void _onPanEnd(DragEndDetails d) {
    if (_status != _TracingStatus.idle) return;
    setState(() {
      _strokes.add([..._currentStroke, null]);
      _currentStroke = [];
    });
  }

  void _clearCanvas() {
    HapticFeedback.lightImpact();
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _showHint = true;
      _status = _TracingStatus.idle;
    });
  }

  // ── KI-Auswertung ─────────────────────────────────────────────────────────

  Future<void> _submitDrawing() async {
    if (_strokes.isEmpty && _currentStroke.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _status = _TracingStatus.evaluating);

    try {
      final imageBytes = await _captureCanvas();
      if (imageBytes == null) {
        _showFallbackResult(success: true); // Fehlerfall → positiv
        return;
      }

      if (_aiModel == null) {
        _showFallbackResult(success: true);
        return;
      }

      final task = _currentTask;
      // Buchstaben-spezifische Hinweise für häufige Verwechslungen
      final letterHints = {
        'L':
            'L has a vertical stroke going DOWN and a horizontal stroke going RIGHT at the bottom. A mirrored L (horizontal going LEFT) is WRONG.',
        'J':
            'J has a vertical stroke with a hook curving LEFT at the bottom. A mirrored J is WRONG.',
        'F':
            'F has horizontal strokes going RIGHT only. A mirrored F is WRONG.',
        'E':
            'E has horizontal strokes going RIGHT only. A mirrored E is WRONG.',
        'G':
            'G opens to the LEFT with a small inward horizontal bar. A mirrored G is WRONG.',
        'K':
            'K has diagonal strokes going to the RIGHT. A mirrored K is WRONG.',
        'R': 'R has the leg going to the RIGHT. A mirrored R is WRONG.',
        'P':
            'P has the bump on the RIGHT side of the vertical stroke. A mirrored P (like q or d) is WRONG.',
        'B': 'B has TWO bumps on the RIGHT side. A mirrored B is WRONG.',
        'D': 'D has the bump on the RIGHT side. A mirrored D is WRONG.',
        'S':
            'S curves first to the right at top, then to the left at bottom. A backwards S is WRONG.',
        'Z':
            'Z has a top horizontal going RIGHT, diagonal going DOWN-LEFT, and bottom horizontal going RIGHT. A mirrored Z is WRONG.',
        'N':
            'N has two vertical strokes connected by a diagonal going DOWN-RIGHT. A mirrored N is WRONG.',
      };
      final hint = task.isLetter ? (letterHints[task.character] ?? '') : '';

      final prompt = task.isLetter
          ? 'Does this handwritten drawing correctly show the letter "${task.character}"? '
                '${hint.isNotEmpty ? "$hint " : ""}'
                'STRICT RULES: orientation and direction MUST be correct. '
                'A mirrored, flipped, or reversed version is WRONG – answer "no". '
                'Only answer "yes" if the letter faces the correct direction. '
                'Be generous with stroke thickness or slight wobble, but NEVER accept wrong orientation. '
                'Answer with only "yes" or "no".'
          : 'Does this handwritten drawing correctly show the digit "${task.character}"? '
                'STRICT: orientation must be correct. '
                'A backwards "3" is WRONG. A "2" drawn as a mirror image is WRONG. '
                '"6" opens downward (the loop is at the bottom), "9" opens upward (loop at top) – do NOT confuse them. '
                '"1" is a single near-vertical stroke only. '
                'Answer with only "yes" or "no".';

      final response = await _aiModel!
          .generateContent([
            Content.multi([
              TextPart(prompt),
              InlineDataPart('image/png', imageBytes),
            ]),
          ])
          .timeout(const Duration(seconds: 10));

      final answer = response.text?.toLowerCase().trim() ?? 'no';
      final isCorrect = answer.startsWith('yes') || answer.contains('ja');
      _showResult(isCorrect: isCorrect);
    } catch (e) {
      debugPrint('TracingGame: AI evaluation error: $e');
      // Bei Timeout oder Fehler → positiv werten (Kind nicht frustrieren)
      _showFallbackResult(success: true);
    }
  }

  Future<Uint8List?> _captureCanvas() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('TracingGame: capture error: $e');
      return null;
    }
  }

  void _showResult({required bool isCorrect}) {
    if (!mounted) return;
    setState(() {
      _status = isCorrect ? _TracingStatus.correct : _TracingStatus.wrong;
      _feedbackEmoji = isCorrect ? '🌟' : '💪';
      _feedbackText = isCorrect ? 'Super gemalt!' : 'Nochmal versuchen!';
      if (isCorrect) _correctCount++;
      _totalAnswered++;
    });
    _feedbackCtrl.forward(from: 0);
    if (!isCorrect) _shakeCtrl.forward(from: 0);
    HapticFeedback.heavyImpact();

    // TTS-Feedback
    final child = ref.read(activeChildProvider);
    if (child != null) {
      final ttsEnabled = ref.read(ttsSettingsProvider(child.id));
      if (ttsEnabled) {
        ref
            .read(ttsControllerProvider.notifier)
            .speak(isCorrect ? _feedbackText : 'Versuch es noch einmal!');
      }
    }

    // XP vergeben
    if (isCorrect) {
      final user = ref.read(authStateChangesProvider).value;
      if (user != null && child != null) {
        ref
            .read(xpServiceProvider)
            .addXP(userId: user.uid, childId: child.id, xpToAdd: 10);
      }
    }

    if (isCorrect) {
      // ── Richtig: Auto-weiter nach 2 Sekunden ─────────────────────
      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _nextTask();
      });
    }
    // ── Falsch: KEIN auto-advance! Buttons werden angezeigt (see build)
  }

  void _showFallbackResult({required bool success}) {
    _showResult(isCorrect: success);
  }

  void _nextTask() {
    if (_taskIndex >= _tasks.length - 1) {
      setState(() => _status = _TracingStatus.finished);
      return;
    }
    setState(() {
      _taskIndex++;
      _strokes.clear();
      _currentStroke = [];
      _showHint = true;
      _status = _TracingStatus.idle;
      _feedbackText = '';
    });
    _feedbackCtrl.reset();
    _shakeCtrl.reset();
    Future.delayed(const Duration(milliseconds: 300), _speakCurrentTask);
  }

  /// Setzt den Canvas zurück damit das Kind die gleiche Aufgabe nochmal malen kann.
  void _retryCurrentTask() {
    HapticFeedback.lightImpact();
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _showHint = true;
      _status = _TracingStatus.idle;
      _feedbackText = '';
    });
    _feedbackCtrl.reset();
    _shakeCtrl.reset();
    Future.delayed(const Duration(milliseconds: 300), _speakCurrentTask);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_status == _TracingStatus.finished) {
      return _FinishedView(
        correct: _correctCount,
        total: _totalRounds,
        colors: widget.subjectColors,
        onBack: () => Navigator.pop(context),
        onRetry: () => setState(() {
          _buildTaskList();
          _taskIndex = 0;
          _correctCount = 0;
          _totalAnswered = 0;
          _strokes.clear();
          _currentStroke = [];
          _showHint = true;
          _status = _TracingStatus.idle;
          Future.delayed(const Duration(milliseconds: 300), _speakCurrentTask);
        }),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildTaskLabel(),
            const SizedBox(height: 8),
            Expanded(child: _buildCanvas()),
            const SizedBox(height: 12),
            _buildControls(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.subjectColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text('✏️', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Malen & Lernen',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          // Fortschritt
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_taskIndex + 1} / $_totalRounds',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskLabel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: widget.subjectColors.first.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    color: widget.subjectColors.first,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _currentTask.ttsPrompt,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: widget.subjectColors.first,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _speakCurrentTask();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: widget.subjectColors.first.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.replay_rounded,
                        color: widget.subjectColors.first,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: _shakeAnim,
        builder: (context, child) => Transform.translate(
          offset: Offset(_shakeAnim.value, 0),
          child: child,
        ),
        child: Stack(
          children: [
            // Canvas Container
            RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: widget.subjectColors.first.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: widget.subjectColors.first.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Stack(
                      children: [
                        // Hint-Buchstabe (grau im Hintergrund)
                        if (_showHint)
                          Center(
                            child: Text(
                              _currentTask.displayHint,
                              style: TextStyle(
                                fontSize: 180,
                                fontWeight: FontWeight.w900,
                                color: widget.subjectColors.first.withOpacity(
                                  0.07,
                                ),
                              ),
                            ),
                          ),
                        // Mallinien-Painter
                        CustomPaint(
                          painter: _DrawingPainter(
                            strokes: _strokes,
                            currentStroke: _currentStroke,
                            color: widget.subjectColors.first,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Feedback-Overlay
            if (_status == _TracingStatus.correct ||
                _status == _TracingStatus.wrong)
              Positioned.fill(
                child: ScaleTransition(
                  scale: _feedbackScale,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: _status == _TracingStatus.correct
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_status == _TracingStatus.correct
                                        ? Colors.green
                                        : Colors.orange)
                                    .withOpacity(0.3),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _feedbackEmoji,
                            style: const TextStyle(fontSize: 56),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _feedbackText,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _status == _TracingStatus.correct
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Ladeindikator
            if (_status == _TracingStatus.evaluating)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: widget.subjectColors.first,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '🔍 Schaue mir das an...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildControls() {
    // ── Bei falscher Antwort: Nochmal / Weiter Buttons ──────────────
    if (_status == _TracingStatus.wrong) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            // 🔄 Nochmal-Button
            GestureDetector(
              onTap: _retryCurrentTask,
              child: Container(
                width: double.infinity,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: widget.subjectColors),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: widget.subjectColors.first.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🔄', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 10),
                    Text(
                      'Nochmal!',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // ➡️ Weiter-Button
            GestureDetector(
              onTap: _nextTask,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: widget.subjectColors.first.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('➡️', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Text(
                      'Weiter',
                      style: TextStyle(
                        fontSize: 18,
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
      );
    }

    // ── Normal: Löschen + Prüfen Buttons ────────────────────────────
    final canSubmit =
        (_strokes.isNotEmpty || _currentStroke.isNotEmpty) &&
        _status == _TracingStatus.idle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Löschen
          GestureDetector(
            onTap: _clearCanvas,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.grey,
                size: 30,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Prüfen-Button
          Expanded(
            child: GestureDetector(
              onTap: canSubmit ? _submitDrawing : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 64,
                decoration: BoxDecoration(
                  gradient: canSubmit
                      ? LinearGradient(colors: widget.subjectColors)
                      : const LinearGradient(
                          colors: [Color(0xFFDDDDDD), Color(0xFFCCCCCC)],
                        ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: canSubmit
                      ? [
                          BoxShadow(
                            color: widget.subjectColors.first.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      canSubmit ? '✅' : '✏️',
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      canSubmit ? 'Fertig!' : 'Male zuerst',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status ────────────────────────────────────────────────────────────────────

enum _TracingStatus { idle, evaluating, correct, wrong, finished }

// ── Custom Painter ────────────────────────────────────────────────────────────

class _DrawingPainter extends CustomPainter {
  final List<List<Offset?>> strokes;
  final List<Offset?> currentStroke;
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
      ..strokeWidth = 14
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
      drawStroke(currentStroke);
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter old) => true; // live redraw on every stroke update
}

// ── Finished View ─────────────────────────────────────────────────────────────

class _FinishedView extends StatelessWidget {
  final int correct;
  final int total;
  final List<Color> colors;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  const _FinishedView({
    required this.correct,
    required this.total,
    required this.colors,
    required this.onBack,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final allCorrect = correct == total;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  allCorrect
                      ? '🏆'
                      : correct >= total ~/ 2
                      ? '🌟'
                      : '💪',
                  style: const TextStyle(fontSize: 80),
                ),
                const SizedBox(height: 16),
                Text(
                  allCorrect
                      ? 'Perfekt gemalt!'
                      : correct >= total ~/ 2
                      ? 'Toll gemacht!'
                      : 'Weiter üben!',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: colors.first,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    '$correct / $total',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Nochmal
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: colors.first.withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🔄', style: TextStyle(fontSize: 26)),
                        SizedBox(width: 10),
                        Text(
                          'Nochmal!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Zurück
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🏠', style: TextStyle(fontSize: 26)),
                        SizedBox(width: 10),
                        Text(
                          'Zurück',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF555555),
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
    );
  }
}
