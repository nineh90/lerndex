import 'dart:math';
import 'package:flutter/material.dart';

// ============================================================================
// AVATAR-FORTSCHRITTSANZEIGE – Quiz-Header Widget
//
// Zeigt den Avatar des Kindes, der von Station zu Station hüpft.
// Jede Station ist ein Blatt (🍃). Bei richtiger Antwort wird es
// zum Stern (⭐), bei falscher bleibt es ein welkes Blatt (🍂).
//
// Am Ende des Quiz (wenn isFinished == true):
// • Bei ≥ 4/5 richtig: Avatar verwandelt sich in einen Schmetterling 🦋
//   mit Scale+Rotation-Animation
// • Bei < 4/5: Avatar bleibt, bekommt ein ermutigendes Glow
//
// Nutzung im Quiz-Screen:
// ```dart
// AvatarProgressBar(
//   totalSteps: 5,
//   currentStep: _currentIndex,
//   stepResults: _stepResults,       // List<bool?> – null=unbeantwortet
//   isFinished: _isFinished,
//   correctCount: _correctAnswers,
//   avatarId: child?.selectedAvatar,
//   childName: child?.name ?? '',
//   subjectColor: widget.subjectColors.first,
// )
// ```
// ============================================================================

class AvatarProgressBar extends StatefulWidget {
  /// Gesamtanzahl der Fragen
  final int totalSteps;

  /// Aktuelle Frage (0-basiert)
  final int currentStep;

  /// Ergebnis pro Frage: true = richtig, false = falsch, null = unbeantwortet
  final List<bool?> stepResults;

  /// Quiz ist beendet
  final bool isFinished;

  /// Anzahl richtiger Antworten (für Schmetterling-Entscheidung)
  final int correctCount;

  /// Avatar-ID des Kindes (für Asset-Bild)
  final String? avatarId;

  /// Name des Kindes (Fallback für Initialen)
  final String childName;

  /// Fachfarbe (für Border, Glow, Linie)
  final Color subjectColor;

  const AvatarProgressBar({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    required this.stepResults,
    required this.isFinished,
    required this.correctCount,
    required this.avatarId,
    required this.childName,
    required this.subjectColor,
  });

  @override
  State<AvatarProgressBar> createState() => _AvatarProgressBarState();
}

class _AvatarProgressBarState extends State<AvatarProgressBar>
    with TickerProviderStateMixin {
  // Hüpf-Animation: Avatar springt leicht hoch beim Stationswechsel
  late AnimationController _hopController;
  late Animation<double> _hopAnim;

  // Schmetterling-Transformation am Ende
  late AnimationController _butterflyController;
  late Animation<double> _butterflyScale;
  late Animation<double> _butterflyRotation;

  // Merkt sich den letzten Step um Hüpf-Animation auszulösen
  int _lastStep = 0;

  // Schmetterling bereits gezeigt?
  bool _showButterfly = false;

  @override
  void initState() {
    super.initState();
    _lastStep = widget.currentStep;

    // Hüpf-Animation (kurzer Bounce nach oben)
    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _hopAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -12.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -12.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 60,
      ),
    ]).animate(_hopController);

    // Schmetterling-Animation
    _butterflyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _butterflyScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.5,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.5,
          end: 1.4,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 70,
      ),
    ]).animate(_butterflyController);
    _butterflyRotation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(
        parent: _butterflyController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AvatarProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Step hat sich geändert → Hüpf-Animation
    if (widget.currentStep != _lastStep) {
      _lastStep = widget.currentStep;
      _hopController.forward(from: 0);
    }

    // Quiz gerade beendet → Schmetterling-Check
    if (widget.isFinished && !oldWidget.isFinished) {
      if (widget.correctCount >= 4) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() => _showButterfly = true);
            _butterflyController.forward();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _hopController.dispose();
    _butterflyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final stepWidth = totalWidth / widget.totalSteps;
          final avatarX =
              (widget.currentStep * stepWidth) + (stepWidth / 2) - 18;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Fortschrittslinie (Hintergrund) ─────────────────────
              Positioned(
                top: 24,
                left: stepWidth / 2,
                right: stepWidth / 2,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Farbige Fortschrittslinie (bis aktuellem Step) ──────
              Positioned(
                top: 24,
                left: stepWidth / 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  height: 3,
                  width: widget.totalSteps > 1
                      ? (widget.currentStep / (widget.totalSteps - 1)) *
                            (totalWidth - stepWidth)
                      : 0,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.7),
                        Colors.white.withValues(alpha: 0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Stationen (Blätter / Sterne / Welke Blätter) ───────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(widget.totalSteps, (i) {
                  return _StationIcon(
                    result: i < widget.stepResults.length
                        ? widget.stepResults[i]
                        : null,
                    isCurrent: i == widget.currentStep && !widget.isFinished,
                    subjectColor: widget.subjectColor,
                  );
                }),
              ),

              // ── Avatar / Schmetterling ──────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                left: avatarX.clamp(0.0, totalWidth - 36),
                top: 0,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_hopAnim, _butterflyController]),
                  builder: (_, child) {
                    final hopOffset = _hopController.isAnimating
                        ? _hopAnim.value
                        : 0.0;
                    final bScale = _butterflyController.isAnimating
                        ? _butterflyScale.value
                        : (_showButterfly ? 1.4 : 1.0);
                    final bRotation = _butterflyController.isAnimating
                        ? _butterflyRotation.value
                        : 0.0;

                    return Transform.translate(
                      offset: Offset(0, hopOffset),
                      child: Transform.scale(
                        scale: bScale,
                        child: Transform.rotate(angle: bRotation, child: child),
                      ),
                    );
                  },
                  child: _showButterfly
                      ? _buildButterflyAvatar()
                      : _buildAvatarCircle(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Avatar-Kreis (normaler Zustand) ─────────────────────────────────────

  Widget _buildAvatarCircle() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: widget.subjectColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: widget.subjectColor.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: widget.avatarId != null
          ? ClipOval(
              child: Image.asset(
                'assets/images/${widget.avatarId}.webp',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildInitials(),
              ),
            )
          : _buildInitials(),
    );
  }

  // ── Schmetterling-Avatar (nach Transformation) ──────────────────────────

  Widget _buildButterflyAvatar() {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Glow-Effekt
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                  blurRadius: 16,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          // Schmetterling-Emoji
          const Text('🦋', style: TextStyle(fontSize: 28)),
          // Kleine Funken drumherum
          ..._buildSparkles(),
        ],
      ),
    );
  }

  List<Widget> _buildSparkles() {
    if (!_butterflyController.isAnimating &&
        _butterflyController.status != AnimationStatus.completed) {
      return [];
    }
    final rng = Random(42); // Fester Seed für konsistente Positionen
    return List.generate(6, (i) {
      final angle = (i * 60) * pi / 180;
      final dist = 18.0 + rng.nextDouble() * 6;
      return Positioned(
        left: 18 + cos(angle) * dist - 4,
        top: 18 + sin(angle) * dist - 4,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 400 + i * 80),
          curve: Curves.easeOut,
          builder: (_, v, __) => Opacity(
            opacity: (1 - v).clamp(0, 1),
            child: Transform.scale(
              scale: 0.5 + v * 0.5,
              child: const Text('✨', style: TextStyle(fontSize: 8)),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        widget.childName.isNotEmpty ? widget.childName[0].toUpperCase() : '😊',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: widget.subjectColor,
        ),
      ),
    );
  }
}

// ============================================================================
// STATION ICON – Einzelne Station auf der Fortschrittslinie
// ============================================================================

class _StationIcon extends StatelessWidget {
  /// null = unbeantwortet, true = richtig, false = falsch
  final bool? result;

  /// Ist dies die aktuelle Frage?
  final bool isCurrent;

  /// Fachfarbe für Highlight
  final Color subjectColor;

  const _StationIcon({
    required this.result,
    required this.isCurrent,
    required this.subjectColor,
  });

  @override
  Widget build(BuildContext context) {
    String icon;
    double size;

    if (result == null) {
      // Unbeantwortet → Blatt
      icon = '🍃';
      size = isCurrent ? 20 : 16;
    } else if (result == true) {
      // Richtig → Stern
      icon = '⭐';
      size = 20;
    } else {
      // Falsch → Welkes Blatt
      icon = '🍂';
      size = 18;
    }

    return SizedBox(
      width: 32,
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Platz für Avatar oben
          const SizedBox(height: 8),
          // Station
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.elasticOut,
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Text(
              icon,
              key: ValueKey('station-$result-$isCurrent'),
              style: TextStyle(fontSize: size),
            ),
          ),
        ],
      ),
    );
  }
}
