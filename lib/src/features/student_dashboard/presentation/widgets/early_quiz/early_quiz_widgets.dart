import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../avatar_progress_bar.dart';

// ============================================================================
// GEMEINSAME WIDGETS der Quizze für Klasse 1–2
// (Zahlen, Buchstaben, Farben & Formen)
// ============================================================================

/// Gemeinsame Felder der Aufgaben aller drei Quizze.
abstract interface class EarlyTask {
  String get questionText;
  List<String> get options;
  String get correctAnswer;
  String get feedbackCorrect;
  String get feedbackWrong;

  /// Schwierigkeitsstufe 1–5 (Badge im Kopf).
  int get difficultyLevel;
}

const _textDark = Color(0xFF1A1A2E);

/// Sternförmige Konfetti-Teilchen.
Path quizStarPath(Size size) {
  final path = Path();
  final cx = size.width / 2;
  final cy = size.height / 2;
  final outerR = size.width / 2;
  final innerR = size.width / 4;
  for (int i = 0; i < 5; i++) {
    final outerAngle = (i * 72 - 90) * pi / 180;
    final innerAngle = ((i * 72) + 36 - 90) * pi / 180;
    if (i == 0) {
      path.moveTo(cx + outerR * cos(outerAngle), cy + outerR * sin(outerAngle));
    } else {
      path.lineTo(cx + outerR * cos(outerAngle), cy + outerR * sin(outerAngle));
    }
    path.lineTo(cx + innerR * cos(innerAngle), cy + innerR * sin(innerAngle));
  }
  path.close();
  return path;
}

const _confettiColors = [
  Color(0xFFFFD700),
  Color(0xFFFFA500),
  Color(0xFFFF6B6B),
  Color(0xFF4ECDC4),
  Color(0xFFFFE66D),
  Color(0xFFFF69B4),
];

/// Konfetti bei einer richtigen Antwort.
class AnswerConfetti extends StatelessWidget {
  const AnswerConfetti({super.key, required this.controller});

  final ConfettiController controller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConfettiWidget(
        confettiController: controller,
        blastDirectionality: BlastDirectionality.explosive,
        shouldLoop: false,
        numberOfParticles: 15,
        maxBlastForce: 20,
        minBlastForce: 8,
        emissionFrequency: 0.05,
        gravity: 0.2,
        colors: _confettiColors,
        createParticlePath: quizStarPath,
      ),
    );
  }
}

/// Runder Knopf im Quiz-Kopf (Zurück, Vorlesen) – 48 dp, mit Label für
/// Screenreader.
class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// Kopfzeile: Zurück, Fortschritt mit Avatar, Vorlesen, Stufen-Badge.
class EarlyQuizHeader extends StatelessWidget {
  const EarlyQuizHeader({
    super.key,
    required this.taskCount,
    required this.currentIndex,
    required this.stepResults,
    required this.avatarId,
    required this.childName,
    required this.level,
    required this.subjectColor,
    required this.stageEmoji,
    required this.stageName,
    required this.isSpeaking,
    required this.onBack,
    required this.onSpeak,
  });

  final int taskCount;
  final int currentIndex;
  final List<bool?> stepResults;
  final String? avatarId;
  final String childName;
  final int level;
  final Color subjectColor;
  final String stageEmoji;
  final String stageName;
  final bool isSpeaking;
  final VoidCallback onBack;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _HeaderCircleButton(
                icon: Icons.arrow_back_rounded,
                label: 'Zurück',
                onTap: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AvatarProgressBar(
                  totalSteps: taskCount,
                  currentStep: currentIndex,
                  stepResults: stepResults,
                  avatarId: avatarId,
                  childName: childName,
                  subjectColor: subjectColor,
                ),
              ),
              const SizedBox(width: 8),
              _HeaderCircleButton(
                icon: isSpeaking
                    ? Icons.volume_up_rounded
                    : Icons.volume_up_outlined,
                label: 'Aufgabe vorlesen',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSpeak();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  'Level $level · $stageName',
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
}

/// Großer Antwort-Knopf. Text schrumpft notfalls (FittedBox), damit Zahlen
/// und Wörter auch bei großer Systemschrift nicht abgeschnitten werden.
class EarlyAnswerButton extends StatefulWidget {
  const EarlyAnswerButton({
    super.key,
    required this.label,
    required this.colors,
    required this.onTap,
    this.enabled = true,
    this.fontSize = 26,
    this.verticalPadding = 18,
  });

  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool enabled;
  final double fontSize;
  final double verticalPadding;

  @override
  State<EarlyAnswerButton> createState() => _EarlyAnswerButtonState();
}

class _EarlyAnswerButtonState extends State<EarlyAnswerButton>
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
    return Semantics(
      button: true,
      enabled: widget.enabled,
      child: GestureDetector(
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
            padding: EdgeInsets.symmetric(
              vertical: widget.verticalPadding,
              horizontal: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.colors.first.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w900,
                    color: widget.colors.first,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vier Antworten im 2×2-Raster.
class EarlyAnswerGrid extends StatelessWidget {
  const EarlyAnswerGrid({
    super.key,
    required this.options,
    required this.colors,
    required this.enabled,
    required this.onSelect,
    this.childAspectRatio = 2.2,
    this.fontSize = 26,
    this.verticalPadding = 18,
  });

  final List<String> options;
  final List<Color> colors;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final double childAspectRatio;
  final double fontSize;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: childAspectRatio,
      children: options
          .map(
            (opt) => EarlyAnswerButton(
              label: opt,
              colors: colors,
              enabled: enabled,
              fontSize: fontSize,
              verticalPadding: verticalPadding,
              onTap: () => onSelect(opt),
            ),
          )
          .toList(),
    );
  }
}

/// Antworten nebeneinander in einer Reihe (z.B. < = > oder zwei Wörter).
class EarlyAnswerRow extends StatelessWidget {
  const EarlyAnswerRow({
    super.key,
    required this.options,
    required this.colors,
    required this.enabled,
    required this.onSelect,
    this.fontSize = 26,
    this.verticalPadding = 18,
  });

  final List<String> options;
  final List<Color> colors;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final double fontSize;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options
          .map(
            (opt) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: EarlyAnswerButton(
                  label: opt,
                  colors: colors,
                  enabled: enabled,
                  fontSize: fontSize,
                  verticalPadding: verticalPadding,
                  onTap: () => onSelect(opt),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Grünes/rotes Feedback über der Aufgabe, bei falscher Antwort mit
/// „Nochmal“ und „Weiter“.
class QuizFeedbackOverlay extends StatelessWidget {
  const QuizFeedbackOverlay({
    super.key,
    required this.wasCorrect,
    required this.text,
    required this.showRetryChoice,
    required this.animation,
    required this.onRetry,
    required this.onNext,
    this.fontSize = 22,
  });

  final bool wasCorrect;
  final String text;
  final bool showRetryChoice;
  final Animation<double> animation;
  final VoidCallback onRetry;
  final VoidCallback onNext;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: (wasCorrect ? Colors.green.shade400 : Colors.red.shade400)
              .withValues(alpha: 0.92),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: animation,
                  builder: (_, _) {
                    final scale = 1.0 + sin(animation.value * pi) * 0.3;
                    return Transform.scale(
                      scale: scale,
                      child: Text(
                        wasCorrect ? '✅' : '❌',
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
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ),
                if (showRetryChoice) ...[
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RetryButton(
                        emoji: '🔄',
                        label: 'Nochmal',
                        onTap: onRetry,
                      ),
                      const SizedBox(width: 16),
                      _RetryButton(emoji: '➡️', label: 'Weiter', onTap: onNext),
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
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
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
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aussehen der Liste „Diese Aufgaben nochmal üben“.
class WrongTaskStyle {
  const WrongTaskStyle({
    this.questionFontSize = 16,
    this.questionWeight = FontWeight.w700,
    this.answerFontSize = 16,
    this.answerPrefix = '→ ',
    this.answerPaddingH = 10,
  });

  final double questionFontSize;
  final FontWeight questionWeight;
  final double answerFontSize;
  final String answerPrefix;
  final double answerPaddingH;
}

/// Abschluss-Bildschirm: Pokal/Stern, Sterne je Aufgabe, verdiente XP,
/// Aufgaben zum Üben, Home-Knopf.
class EarlyQuizFinishScreen extends StatelessWidget {
  const EarlyQuizFinishScreen({
    super.key,
    required this.subjectColors,
    required this.taskCount,
    required this.correctCount,
    required this.earnedXP,
    required this.isPerfect,
    required this.showConfetti,
    required this.wrongTasks,
    required this.confettiController,
    required this.onHome,
    this.wrongTaskStyle = const WrongTaskStyle(),
  });

  final List<Color> subjectColors;
  final int taskCount;
  final int correctCount;
  final int earnedXP;
  final bool isPerfect;
  final bool showConfetti;

  /// (Frage, richtige Antwort) der beim ersten Versuch falschen Aufgaben.
  final List<(String, String)> wrongTasks;
  final ConfettiController confettiController;
  final VoidCallback onHome;
  final WrongTaskStyle wrongTaskStyle;

  @override
  Widget build(BuildContext context) {
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
              SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (_, v, _) => Transform.scale(
                        scale: v,
                        child: Text(
                          isPerfect ? '🏆' : '🌟',
                          style: const TextStyle(fontSize: 100),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isPerfect ? 'Perfekt!' : 'Super gemacht!',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildResultCard(),
                    if (wrongTasks.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildWrongTasks(),
                    ],
                    const SizedBox(height: 36),
                    Semantics(
                      button: true,
                      label: 'Zurück zur Übersicht',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: onHome,
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
                            color: subjectColors.first,
                            size: 44,
                          ),
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
                    confettiController: confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    shouldLoop: false,
                    numberOfParticles: 30,
                    maxBlastForce: 25,
                    minBlastForce: 10,
                    emissionFrequency: 0.04,
                    gravity: 0.15,
                    colors: const [..._confettiColors, Color(0xFF7C4DFF)],
                    createParticlePath: quizStarPath,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
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
          Semantics(
            label: '$correctCount von $taskCount beim ersten Versuch richtig',
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                taskCount,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 400 + i * 150),
                    curve: Curves.elasticOut,
                    builder: (_, v, _) => Transform.scale(
                      scale: v,
                      child: Text(
                        i < correctCount ? '⭐' : '☆',
                        style: TextStyle(
                          fontSize: 36,
                          color: i < correctCount
                              ? Colors.amber
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // XP (in Kl. 1–2 als ⭐ dargestellt)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                    // Dunkles Braun statt amber.shade700: auf amber.shade50
                    // sonst zu wenig Kontrast.
                    const Text(
                      'in diesem Quiz',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6D4C00),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWrongTasks() {
    final style = wrongTaskStyle;
    return Container(
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
                  const Text('❌', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.$1,
                      style: TextStyle(
                        fontSize: style.questionFontSize,
                        fontWeight: style.questionWeight,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: style.answerPaddingH,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${style.answerPrefix}${t.$2}',
                      style: TextStyle(
                        fontSize: style.answerFontSize,
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
    );
  }
}
