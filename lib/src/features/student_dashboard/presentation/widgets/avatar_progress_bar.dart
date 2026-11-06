import 'package:flutter/material.dart';

// ============================================================================
// AVATAR-FORTSCHRITTSANZEIGE – Quiz-Header Widget
//
// Zeigt den Avatar des Kindes, der von Station zu Station hüpft.
// Jede Station ist ein Blatt (🍃). Bei richtiger Antwort wird es
// zum Stern (⭐), bei falscher bleibt es ein welkes Blatt (🍂).
//
// Nutzung im Quiz-Screen:
// ```dart
// AvatarProgressBar(
//   totalSteps: 5,
//   currentStep: _currentIndex,
//   stepResults: _stepResults,       // List<bool?> – null=unbeantwortet
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
    required this.avatarId,
    required this.childName,
    required this.subjectColor,
  });

  @override
  State<AvatarProgressBar> createState() => _AvatarProgressBarState();
}

class _AvatarProgressBarState extends State<AvatarProgressBar>
    with SingleTickerProviderStateMixin {
  // Hüpf-Animation: Avatar springt leicht hoch beim Stationswechsel
  late AnimationController _hopController;
  late Animation<double> _hopAnim;

  // Merkt sich den letzten Step um Hüpf-Animation auszulösen
  int _lastStep = 0;

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
  }

  @override
  void didUpdateWidget(covariant AvatarProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Step hat sich geändert → Hüpf-Animation
    if (widget.currentStep != _lastStep) {
      _lastStep = widget.currentStep;
      _hopController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hopController.dispose();
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
                    isCurrent: i == widget.currentStep,
                    subjectColor: widget.subjectColor,
                  );
                }),
              ),

              // ── Avatar ──────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                left: avatarX.clamp(0.0, totalWidth - 36),
                top: 0,
                child: AnimatedBuilder(
                  animation: _hopAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(
                      0,
                      _hopController.isAnimating ? _hopAnim.value : 0.0,
                    ),
                    child: child,
                  ),
                  child: _buildAvatarCircle(),
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
                errorBuilder: (_, _, _) => _buildInitials(),
              ),
            )
          : _buildInitials(),
    );
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
