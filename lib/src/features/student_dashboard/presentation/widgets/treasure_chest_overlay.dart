import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// SCHATZKISTEN-OVERLAY – Wird nach dem Quiz gezeigt (≥ 4/5 richtig)
//
// Ablauf:
// 1. Overlay erscheint mit dunklem Hintergrund
// 2. Goldene Schatzkiste wackelt (RotationTransition, 1s)
// 3. Text: "Du hast eine Schatzkiste gefunden!"
// 4. Kind tippt auf Kiste → Kiste öffnet sich
//    - AnimatedSwitcher: 🎁 → ✨⭐✨
//    - Sterne fliegen nach oben (SlideTransition)
//    - Haptic Feedback
// 5. Verdiente Sterne werden angezeigt
// 6. "Weiter"-Button erscheint
//
// Nutzung:
// ```dart
// showDialog(
//   context: context,
//   barrierDismissible: false,
//   builder: (_) => TreasureChestOverlay(
//     earnedStars: 8,
//     isPerfect: true,
//     onDismiss: () => Navigator.pop(context),
//   ),
// );
// ```
// ============================================================================

class TreasureChestOverlay extends StatefulWidget {
  /// Anzahl der verdienten Sterne
  final int earnedStars;

  /// War das Ergebnis perfekt (alle richtig)?
  final bool isPerfect;

  /// Callback wenn das Overlay geschlossen wird
  final VoidCallback onDismiss;

  const TreasureChestOverlay({
    super.key,
    required this.earnedStars,
    required this.isPerfect,
    required this.onDismiss,
  });

  @override
  State<TreasureChestOverlay> createState() => _TreasureChestOverlayState();
}

class _TreasureChestOverlayState extends State<TreasureChestOverlay>
    with TickerProviderStateMixin {
  // Phasen
  bool _isOpened = false;
  bool _showStars = false;
  bool _showButton = false;

  // Wackel-Animation für die Kiste
  late AnimationController _wobbleController;
  late Animation<double> _wobbleAnim;

  // Scale-Animation beim Öffnen
  late AnimationController _openController;
  late Animation<double> _openScale;

  // Einblende-Animation für das Overlay
  late AnimationController _fadeController;

  // Stern-Flug-Animation
  late AnimationController _starFlyController;

  @override
  void initState() {
    super.initState();

    // Fade-In des Overlays
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    // Kiste wackelt
    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _wobbleAnim =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: 0.05), weight: 25),
          TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 25),
          TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.03), weight: 25),
          TweenSequenceItem(tween: Tween(begin: 0.03, end: 0), weight: 25),
        ]).animate(
          CurvedAnimation(parent: _wobbleController, curve: Curves.easeInOut),
        );

    // Wackeln in Schleife
    _wobbleController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_isOpened) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && !_isOpened) _wobbleController.forward(from: 0);
        });
      }
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _wobbleController.forward();
    });

    // Öffnungs-Animation
    _openController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _openScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.7,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.7,
          end: 1.3,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 70,
      ),
    ]).animate(_openController);

    // Stern-Flug
    _starFlyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _wobbleController.dispose();
    _openController.dispose();
    _starFlyController.dispose();
    super.dispose();
  }

  void _openChest() {
    if (_isOpened) return;

    HapticFeedback.mediumImpact();
    setState(() => _isOpened = true);
    _wobbleController.stop();
    _openController.forward();

    // Sterne fliegen nach 300ms
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _showStars = true);
        _starFlyController.forward();
        HapticFeedback.lightImpact();
      }
    });

    // Button nach 1.2s
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showButton = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: Material(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Titel ───────────────────────────────────────────────
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _isOpened ? 0.0 : 1.0,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    widget.isPerfect
                        ? '🏆 Perfekt! Eine goldene Kiste!'
                        : '✨ Du hast eine Schatzkiste gefunden!',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              // ── Schatzkiste ─────────────────────────────────────────
              GestureDetector(
                onTap: _openChest,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_wobbleAnim, _openScale]),
                  builder: (_, child) {
                    final wobble = _wobbleController.isAnimating
                        ? _wobbleAnim.value
                        : 0.0;
                    final scale = _openController.isAnimating
                        ? _openScale.value
                        : (_isOpened ? 1.3 : 1.0);

                    return Transform.rotate(
                      angle: wobble,
                      child: Transform.scale(scale: scale, child: child),
                    );
                  },
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Glow-Effekt (nur bei geöffnet)
                        if (_isOpened)
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFFD700,
                                  ).withValues(alpha: 0.5),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          ),

                        // Kiste / Geöffnete Kiste
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          switchInCurve: Curves.elasticOut,
                          transitionBuilder: (child, animation) {
                            return ScaleTransition(
                              scale: animation,
                              child: child,
                            );
                          },
                          child: Text(
                            _isOpened
                                ? (widget.isPerfect ? '👑' : '⭐')
                                : (widget.isPerfect ? '🎁' : '📦'),
                            key: ValueKey(_isOpened),
                            style: const TextStyle(fontSize: 100),
                          ),
                        ),

                        // Fliegende Sterne
                        if (_showStars) ..._buildFlyingStars(),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Tipp-Hinweis ────────────────────────────────────────
              if (!_isOpened)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: 1.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('👆', style: TextStyle(fontSize: 20)),
                          SizedBox(width: 8),
                          Text(
                            'Tippe auf die Kiste!',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Sterne-Gewinn Anzeige ───────────────────────────────
              if (_isOpened)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _showStars ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('⭐', style: TextStyle(fontSize: 32)),
                          const SizedBox(width: 10),
                          Text(
                            '+${widget.earnedStars}',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Weiter-Button ───────────────────────────────────────
              if (_showButton)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onDismiss();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 36,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🏠', style: TextStyle(fontSize: 24)),
                            SizedBox(width: 10),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Color(0xFFFF8C00),
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Fliegende Sterne (aus der Kiste) ──────────────────────────────────────

  List<Widget> _buildFlyingStars() {
    final rng = Random(42);
    return List.generate(8, (i) {
      final angle = (i * 45) * pi / 180;
      final distance = 50.0 + rng.nextDouble() * 30;

      return AnimatedBuilder(
        animation: _starFlyController,
        builder: (_, __) {
          final progress = Curves.easeOut.transform(
            (_starFlyController.value * 2 - i * 0.08).clamp(0.0, 1.0),
          );
          final dx = cos(angle) * distance * progress;
          final dy = sin(angle) * distance * progress - (progress * 20);
          final opacity = (1 - progress * 0.7).clamp(0.0, 1.0);
          final scale = 0.5 + progress * 0.8;

          return Transform.translate(
            offset: Offset(dx, dy),
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: const Text('⭐', style: TextStyle(fontSize: 20)),
              ),
            ),
          );
        },
      );
    });
  }
}
