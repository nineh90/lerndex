import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'early_quiz/early_quiz_state_mixin.dart';
import 'early_quiz/early_quiz_widgets.dart';
import 'letter_task_engine.dart';

// ============================================================================
// LETTER QUIZ SCREEN – Klasse 1 & 2 (Buchstaben)
//
// 5 Aufgabentypen, jeder Typ kommt pro Runde genau einmal vor:
//   anlaut       – Welcher Buchstabe beginnt das Bild?
//   grossKlein   – Großbuchstabe → passender Kleinbuchstabe
//   bildWort     – Bild → Wort mit Lücke, Buchstabe finden
//   buchstabeMalen – Buchstabe malen, Vertex AI prüft
//   reihenfolge  – A B __ D → fehlender Buchstabe (Stufe 1)
//   reim         – Was reimt auf X?             (Stufe 2)
//   wortlaenge   – Welches Wort ist länger?     (Stufe 3+)
// ============================================================================

class LetterQuizScreen extends ConsumerStatefulWidget {
  final int grade;
  final List<Color> subjectColors;

  const LetterQuizScreen({
    super.key,
    required this.grade,
    required this.subjectColors,
  });

  @override
  ConsumerState<LetterQuizScreen> createState() => _LetterQuizScreenState();
}

class _LetterQuizScreenState extends ConsumerState<LetterQuizScreen>
    with
        TickerProviderStateMixin,
        EarlyQuizStateMixin<LetterQuizScreen, LetterTask> {
  @override
  String get subject => 'Buchstaben';

  @override
  String get logTag => 'LetterQuiz';

  @override
  List<Color> get subjectColors => widget.subjectColors;

  @override
  List<LetterTask> generateTasks({required int level}) => LetterTaskEngine(
    grade: widget.grade,
    level: level,
  ).generate(EarlyQuizStateMixin.questionCount);

  @override
  String stageName(int stage) => LetterTaskEngine.stageName(stage);

  @override
  String stageEmoji(int stage) => LetterTaskEngine.stageEmoji(stage);

  // ── Sprachausgabe ─────────────────────────────────────────────────────────

  /// Baut TTS-freundlichen Text – keine Unterstriche, keine Sonderzeichen.
  @override
  String ttsTextFor(LetterTask task) {
    switch (task.type) {
      case LetterTaskType.bildWort:
        // Vollständiges Wort vorlesen statt Display-Text mit Lücke
        final word = task.fullWord ?? task.correctAnswer;
        final readable =
            word[0].toUpperCase() + word.substring(1).toLowerCase();
        return 'Welcher Buchstabe fehlt in $readable?';
      case LetterTaskType.reihenfolge:
        // Buchstabenfolge ohne Unterstriche
        final seq = task.letterSequence ?? [];
        final blankIdx = task.blankIndex ?? 2;
        final spoken = seq
            .asMap()
            .entries
            .map((e) => e.key == blankIdx ? 'Lücke' : e.value)
            .join(', ');
        return '$spoken – welcher Buchstabe fehlt?';
      default:
        return task.questionText;
    }
  }

  // ── Frage-Widgets ─────────────────────────────────────────────────────────

  @override
  Widget buildQuestionWidget(LetterTask task) {
    switch (task.type) {
      case LetterTaskType.anlaut:
        return _buildAnlautQuestion(task);
      case LetterTaskType.grossKlein:
        return _buildGrossKleinQuestion(task);
      case LetterTaskType.bildWort:
        return _buildBildWortQuestion(task);
      case LetterTaskType.buchstabeMalen:
        return _buildBuchstabeMalenQuestion(task);
      case LetterTaskType.reihenfolge:
        return _buildReihenfolgeQuestion(task);
      case LetterTaskType.reim:
        return _buildReimQuestion(task);
      case LetterTaskType.wortlaenge:
        return _buildWortlaengeQuestion(task);
    }
  }

  /// 🐸 → Welcher Buchstabe beginnt das?
  Widget _buildAnlautQuestion(LetterTask task) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: bounceAnim.value, child: child),
          child: Text(task.emoji ?? '❓', style: const TextStyle(fontSize: 80)),
        ),
        const SizedBox(height: 16),
        Text(
          task.questionText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  /// A → welcher Kleinbuchstabe?
  Widget _buildGrossKleinQuestion(LetterTask task) {
    return Column(
      children: [
        const Text('🔠', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: bounceAnim.value, child: child),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: widget.subjectColors.first.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.subjectColors.first.withValues(alpha: 0.4),
                width: 3,
              ),
            ),
            child: Center(
              child: Text(
                task.emoji ?? '?',
                style: TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.w900,
                  color: widget.subjectColors.first,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          task.questionText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  /// 🐱 → K_TZE: welcher Buchstabe fehlt?
  Widget _buildBildWortQuestion(LetterTask task) {
    final word = task.fullWord ?? '';
    final missingIdx = task.missingIndex ?? 0;

    return Column(
      children: [
        Text(task.emoji ?? '❓', style: const TextStyle(fontSize: 72)),
        const SizedBox(height: 16),
        // Wort mit Lücke als Buchstaben-Kästchen. Größe aus der verfügbaren
        // Breite: 7 Buchstaben à 38 dp passen auf 360-dp-Geräten nicht.
        LayoutBuilder(
          builder: (context, constraints) {
            final letters = word.characters.toList();
            const gap = 6.0;
            final boxW =
                ((constraints.maxWidth - letters.length * gap) / letters.length)
                    .clamp(22.0, 38.0);
            final boxH = boxW * 44 / 38;
            final fontSize = boxW * 20 / 38;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: letters.asMap().entries.map((e) {
                final isBlank = e.key == missingIdx;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                  child: Container(
                    width: boxW,
                    height: boxH,
                    decoration: BoxDecoration(
                      color: isBlank
                          ? widget.subjectColors.first.withValues(alpha: 0.08)
                          : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(10),
                      border: isBlank
                          ? Border.all(
                              color: widget.subjectColors.first,
                              width: 2.5,
                            )
                          : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isBlank ? '?' : e.value,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w900,
                          color: isBlank
                              ? widget.subjectColors.first.withValues(
                                  alpha: 0.4,
                                )
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Welcher Buchstabe fehlt?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// Male den Buchstaben X!
  Widget _buildBuchstabeMalenQuestion(LetterTask task) {
    return Column(
      children: [
        const Text('✏️', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: bounceAnim.value, child: child),
          child: Text(
            'Male den Buchstaben\n${task.letterToDraw ?? task.correctAnswer}!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A2E),
              height: 1.2,
            ),
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

  /// A B __ D
  Widget _buildReihenfolgeQuestion(LetterTask task) {
    final seq = task.letterSequence ?? [];
    final blankIdx = task.blankIndex ?? 2;

    return Column(
      children: [
        const Text('🔤', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 8),
        const Text(
          'Welcher Buchstabe fehlt?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: seq.asMap().entries.map((e) {
            final isBlank = e.key == blankIdx;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
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
                          e.value,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                    ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort_by_alpha_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              'Das ABC hilft dir!',
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

  /// Was reimt sich auf „Haus"?
  Widget _buildReimQuestion(LetterTask task) {
    return Column(
      children: [
        const Text('🎵', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: bounceAnim,
          builder: (_, child) =>
              Transform.scale(scale: bounceAnim.value, child: child),
          child: Text(
            task.questionText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Welches Wort klingt gleich?',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  /// Welches Wort ist länger/kürzer?
  Widget _buildWortlaengeQuestion(LetterTask task) {
    return Column(
      children: [
        const Text('📏', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text(
          task.questionText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tippe das richtige Wort!',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // ── Antwort-Bereich ───────────────────────────────────────────────────────

  @override
  Widget buildAnswerArea(LetterTask task) {
    if (task.type == LetterTaskType.buchstabeMalen) {
      return buildDrawCanvas(onSubmit: () => _submitDrawing(task));
    }
    if (task.type == LetterTaskType.wortlaenge) {
      // 2 Wort-Buttons nebeneinander
      return EarlyAnswerRow(
        options: task.options,
        colors: widget.subjectColors,
        enabled: !showFeedback,
        fontSize: 20,
        onSelect: checkAnswer,
      );
    }
    // 4 Buchstaben-Buttons (2×2)
    return EarlyAnswerGrid(
      options: task.options,
      colors: widget.subjectColors,
      enabled: !showFeedback,
      onSelect: checkAnswer,
    );
  }

  // ── Malprüfung (KI) ───────────────────────────────────────────────────────

  void _submitDrawing(LetterTask task) {
    final letter = task.correctAnswer;
    // Bekannte Verwechslungspaare explizit ansprechen
    final confusables = {
      'B':
          'B has TWO bumps on the RIGHT. A mirrored B or the letter D is WRONG.',
      'D': 'D has the bump on the RIGHT. A mirrored D is WRONG.',
      'P': 'P has the bump on the RIGHT side top. A mirrored P is WRONG.',
      'Q':
          'Q is like O with a small tail at bottom-right. A mirrored Q is WRONG.',
      'S': 'S curves right at top, left at bottom. A reversed S is WRONG.',
      'Z': 'Z goes top-right to bottom-left diagonally. A reversed Z is WRONG.',
      'N': 'N diagonal goes DOWN-RIGHT. A mirrored N is WRONG.',
      'J': 'J hooks to the LEFT at the bottom. A mirrored J is WRONG.',
      'L': 'L has horizontal going RIGHT at bottom. A mirrored L is WRONG.',
      'F': 'F has horizontals going RIGHT. A mirrored F is WRONG.',
      'E': 'E has horizontals going RIGHT. A mirrored E is WRONG.',
      'K': 'K diagonals go RIGHT. A mirrored K is WRONG.',
      'R': 'R leg goes RIGHT. A mirrored R is WRONG.',
      'G': 'G opens LEFT with an inward bar. A mirrored G is WRONG.',
    };
    final hint = confusables[letter] ?? '';

    final prompt =
        'This is a handwritten letter drawn by a young child (age 6-8). '
        'Does this drawing clearly show the uppercase letter "$letter"? '
        'STRICT RULES: '
        '1. Orientation must be correct. ${hint.isNotEmpty ? hint : ""} '
        '2. Allow for typical child handwriting wobble and imperfect strokes. '
        '3. The letter must be clearly recognizable as "$letter" and not another letter. '
        '4. If the canvas looks empty or has only random scribbles, answer false. '
        'Answer ONLY with JSON: {"correct": true} or {"correct": false, "recognized": "<what letter you see>"}';
    submitDrawing(
      expected: letter,
      prompt: prompt,
      // `recognized` ist englischer Freitext der KI – nur anzeigen, wenn es
      // wirklich nur ein Buchstabe ist.
      wrongMessage: (recognized) =>
          recognized.isNotEmpty &&
              recognized.length <= 3 &&
              recognized.toUpperCase() != letter.toUpperCase()
          ? 'Das sieht aus wie ein $recognized – versuch nochmal!'
          : 'Ich kann den Buchstaben nicht lesen – nochmal!',
    );
  }
}
