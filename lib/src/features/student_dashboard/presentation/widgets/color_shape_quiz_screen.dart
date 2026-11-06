import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'early_quiz/early_quiz_state_mixin.dart';
import 'early_quiz/early_quiz_widgets.dart';
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
    with
        TickerProviderStateMixin,
        EarlyQuizStateMixin<ColorShapeQuizScreen, ColorShapeTask> {
  @override
  String get subject => 'Farben & Formen';

  @override
  String get logTag => 'ColorShapeQuiz';

  @override
  List<Color> get subjectColors => widget.subjectColors;

  @override
  List<ColorShapeTask> generateTasks({required int level}) =>
      ColorShapeTaskEngine(
        grade: widget.grade,
        level: level,
      ).generate(EarlyQuizStateMixin.questionCount);

  @override
  String stageName(int stage) => ColorShapeTaskEngine.stageName(stage);

  @override
  String stageEmoji(int stage) => ColorShapeTaskEngine.stageEmoji(stage);

  @override
  double get feedbackFontSize => 20;

  @override
  WrongTaskStyle get wrongTaskStyle =>
      const WrongTaskStyle(questionFontSize: 15, answerFontSize: 14);

  /// Emojis aus dem Feedback-Text entfernen für die Sprachausgabe.
  @override
  String ttsFeedbackText(String text) =>
      text.replaceAll(RegExp(r'[^\x00-\x7F\u00C0-\u017F\s]'), '').trim();

  // ── Sprachausgabe ─────────────────────────────────────────────────────────

  @override
  String ttsTextFor(ColorShapeTask task) {
    switch (task.type) {
      case ColorShapeTaskType.farbMuster:
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

  // ── Frage-Widgets ─────────────────────────────────────────────────────────

  @override
  Widget buildQuestionWidget(ColorShapeTask task) {
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
            animation: bounceAnim,
            builder: (_, child) =>
                Transform.scale(scale: bounceAnim.value, child: child),
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
        const Text(
          'Was kommt als nächstes?',
          textAlign: TextAlign.center,
          style: TextStyle(
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
                color: widget.subjectColors.first.withValues(alpha: 0.1),
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
                    color: widget.subjectColors.first.withValues(alpha: 0.5),
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
          animation: bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: bounceAnim.value, child: child),
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
        if (drawAttempts > 0 &&
            drawAttempts < EarlyQuizStateMixin.maxDrawAttempts)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Versuch ${drawAttempts + 1} von $EarlyQuizStateMixin.maxDrawAttempts',
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

  @override
  Widget buildAnswerArea(ColorShapeTask task) {
    if (task.type == ColorShapeTaskType.formZeichnen) {
      return buildDrawCanvas(onSubmit: () => _submitDrawing(task));
    }
    // 2 Buttons nebeneinander wenn nur 2 Optionen, sonst 2×2
    if (task.options.length <= 2) {
      return EarlyAnswerRow(
        options: task.options,
        colors: widget.subjectColors,
        enabled: !showFeedback,
        fontSize: 22,
        verticalPadding: 16,
        onSelect: checkAnswer,
      );
    }
    return EarlyAnswerGrid(
      options: task.options,
      colors: widget.subjectColors,
      enabled: !showFeedback,
      childAspectRatio: 2.0,
      fontSize: 22,
      verticalPadding: 16,
      onSelect: checkAnswer,
    );
  }

  // ── Malprüfung (KI) ───────────────────────────────────────────────────────

  void _submitDrawing(ColorShapeTask task) {
    final shape = task.correctAnswer;
    final shapeHints = {
      'Kreis':
          'A Kreis (circle) is perfectly round with no corners or edges. A squiggly blob is WRONG.',
      'Dreieck':
          'A Dreieck (triangle) has exactly 3 straight sides and 3 corners.',
      'Quadrat': 'A Quadrat (square) has 4 equal straight sides and 4 corners.',
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
    submitDrawing(
      expected: shape,
      prompt: prompt,
      // `recognized` wird hier bewusst nicht ausgewertet: bei Formen ist das
      // englischer Freitext („a wobbly circle“) und nicht kindgerecht.
      wrongMessage: (_) => 'Das erkenne ich noch nicht als $shape – nochmal!',
    );
  }
}
