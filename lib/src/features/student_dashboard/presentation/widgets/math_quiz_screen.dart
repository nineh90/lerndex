import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'early_quiz/early_quiz_state_mixin.dart';
import 'early_quiz/early_quiz_widgets.dart';
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
//   numberLine      – Zahlenstrahl: richtige Zahl antippen
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
    with
        TickerProviderStateMixin,
        EarlyQuizStateMixin<MathQuizScreen, MathTask> {
  @override
  String get subject => 'Zahlen';

  @override
  String get logTag => 'MathQuiz';

  @override
  List<Color> get subjectColors => widget.subjectColors;

  @override
  List<MathTask> generateTasks({required int level}) => MathTaskEngine(
    grade: widget.grade,
    level: level,
  ).generate(EarlyQuizStateMixin.questionCount);

  @override
  String stageName(int stage) => MathTaskEngine.stageName(stage);

  @override
  String stageEmoji(int stage) => MathTaskEngine.stageEmoji(stage);

  // Für numberLine (Slider)
  double _sliderValue = 0;
  bool _sliderMoved = false;

  @override
  void resetTaskInput() {
    _sliderValue = 0;
    _sliderMoved = false;
  }

  @override
  WrongTaskStyle get wrongTaskStyle => const WrongTaskStyle(
    questionFontSize: 18,
    questionWeight: FontWeight.w800,
    answerPrefix: '= ',
    answerPaddingH: 12,
  );

  // ── Sprachausgabe ─────────────────────────────────────────────────────────

  /// Baut einen TTS-freundlichen Text – ersetzt Symbole durch Wörter.
  @override
  String ttsTextFor(MathTask task) {
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

  // ── Frage-Widgets ─────────────────────────────────────────────────────────

  @override
  Widget buildQuestionWidget(MathTask task) {
    switch (task.type) {
      case MathTaskType.multipleChoice:
      case MathTaskType.fillBlank:
        return _buildFormulaQuestion(task);

      case MathTaskType.comparison:
        return _buildComparisonQuestion(task);

      case MathTaskType.countDots:
        return _buildCountDotsQuestion(task);

      case MathTaskType.numberLine:
        return _buildNumberLineQuestion(task);

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
          animation: bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: bounceAnim.value, child: child),
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
                        color: widget.subjectColors.first.withValues(
                          alpha: 0.08,
                        ),
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
                            color: widget.subjectColors.first.withValues(
                              alpha: 0.4,
                            ),
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
              color: Colors.grey.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              seq.length >= 2 ? 'Schritte: +${seq[1] - seq[0]}' : '',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

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

  Widget _buildDrawAnswerQuestion(MathTask task) {
    return Column(
      children: [
        const Text('✏️', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: bounceAnim.value, child: child),
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
        if (drawAttempts > 0 &&
            drawAttempts < EarlyQuizStateMixin.maxDrawAttempts)
          Padding(
            padding: const EdgeInsets.only(top: 6),
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

  Widget _buildSliderAnswer(MathTask task) {
    final min = (task.lineMin ?? 0).toDouble();
    final max = (task.lineMax ?? 10).toDouble();
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
            onChanged: showFeedback
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
          onTap: _sliderMoved && !showFeedback
              ? () => checkAnswer('${_sliderValue.round()}')
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
                    : 'Erst schieben…',
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

  // ── Antwort-Bereich ───────────────────────────────────────────────────────

  @override
  Widget buildAnswerArea(MathTask task) {
    switch (task.type) {
      case MathTaskType.multipleChoice:
      case MathTaskType.fillBlank:
      case MathTaskType.countDots:
      case MathTaskType.missingNumber:
      case MathTaskType.wordProblem:
        // 4 große Antwort-Buttons (2×2)
        return EarlyAnswerGrid(
          options: task.options,
          colors: widget.subjectColors,
          enabled: !showFeedback,
          fontSize: 28,
          onSelect: checkAnswer,
        );

      case MathTaskType.comparison:
        // 3 große Buttons für < = >
        return EarlyAnswerRow(
          options: task.options,
          colors: widget.subjectColors,
          enabled: !showFeedback,
          fontSize: 36,
          onSelect: checkAnswer,
        );

      case MathTaskType.numberLine:
        return _buildSliderAnswer(task);

      case MathTaskType.drawAnswer:
        return buildDrawCanvas(onSubmit: () => _submitDrawing(task));
    }
  }

  // ── Malprüfung (KI) ───────────────────────────────────────────────────────

  void _submitDrawing(MathTask task) {
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
    submitDrawing(
      expected: expected,
      prompt: prompt,
      // `recognized` ist englischer Freitext der KI – nur anzeigen, wenn es
      // wirklich nur eine Ziffer/Zahl ist.
      wrongMessage: (recognized) =>
          recognized.isNotEmpty &&
              recognized.length <= 3 &&
              recognized != expected
          ? 'Das sieht aus wie eine $recognized — versuch nochmal!'
          : 'Ich kann die Zahl nicht lesen — nochmal!',
    );
  }
}

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
