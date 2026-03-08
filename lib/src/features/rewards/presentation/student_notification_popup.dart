import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../rewards/domain/reward_model.dart';
import '../../rewards/domain/reward_enums.dart';

// ============================================================================
// STUDENT NOTIFICATION POPUP
//
// Ersetzt den gelben Snackbar-Balken im Schülerdashboard durch ein schönes
// animiertes Fullscreen-Popup.
//
// Unterstützte Typen:
//  • rewardUnlocked  → Eltern-Belohnung wurde freigegeben  (mit "Zur Belohnung"-Button)
//  • achievementUnlocked → System-Achievement erreicht     (mit Konfetti)
//  • avatarUnlocked  → Neuer Avatar freigeschaltet         (mit Konfetti)
//  • streakMilestone → Streak-Meilenstein                  (mit Feuer-Animation)
//
// Nutzung:
//   StudentNotificationPopup.show(
//     context,
//     type: StudentNotificationType.rewardUnlocked,
//     reward: someReward,
//     onGoToRewards: () { /* navigate */ },
//   );
// ============================================================================

enum StudentNotificationType {
  rewardUnlocked,
  achievementUnlocked,
  avatarUnlocked,
  streakMilestone,
}

class StudentNotificationPopup extends StatefulWidget {
  final StudentNotificationType type;
  final RewardModel? reward;
  final VoidCallback? onGoToRewards;
  final VoidCallback onDismiss;

  const StudentNotificationPopup({
    super.key,
    required this.type,
    this.reward,
    this.onGoToRewards,
    required this.onDismiss,
  });

  /// Zeigt das Popup. Gibt true zurück wenn der User auf "Zur Belohnung" tippt.
  static Future<bool> show(
    BuildContext context, {
    required StudentNotificationType type,
    RewardModel? reward,
    VoidCallback? onGoToRewards,
  }) async {
    bool wentToRewards = false;

    await showGeneralDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.75),
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, anim, secAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => StudentNotificationPopup(
        type: type,
        reward: reward,
        onGoToRewards: onGoToRewards != null
            ? () {
                wentToRewards = true;
                Navigator.of(ctx).pop();
                onGoToRewards();
              }
            : null,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );

    return wentToRewards;
  }

  @override
  State<StudentNotificationPopup> createState() =>
      _StudentNotificationPopupState();
}

class _StudentNotificationPopupState extends State<StudentNotificationPopup>
    with TickerProviderStateMixin {
  late ConfettiController _confettiController;
  late AnimationController _iconScaleController;
  late AnimationController _pulseController;
  late AnimationController _contentSlideController;
  late AnimationController _buttonSlideController;
  late AnimationController _glowController;

  late Animation<double> _iconScale;
  late Animation<double> _pulse;
  late Animation<Offset> _contentSlide;
  late Animation<double> _contentFade;
  late Animation<Offset> _buttonSlide;
  late Animation<double> _buttonFade;
  late Animation<double> _glow;

  // Partikel für Feuer-Animation (Streak)
  final List<_FireParticle> _fireParticles = [];
  final Random _random = Random();
  late AnimationController _fireController;

  @override
  void initState() {
    super.initState();

    // Konfetti
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 4),
    );

    // Icon erscheint mit elastischem Bounce
    _iconScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _iconScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconScaleController, curve: Curves.elasticOut),
    );

    // Icon pulsiert danach sanft
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Content fährt von unten rein
    _contentSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _contentSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _contentSlideController,
            curve: Curves.easeOutCubic,
          ),
        );
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentSlideController,
        curve: const Interval(0.0, 0.7),
      ),
    );

    // Button erscheint als letztes
    _buttonSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _buttonSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _buttonSlideController,
            curve: Curves.easeOutCubic,
          ),
        );
    _buttonFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_buttonSlideController);

    // Leuchteffekt um das Icon
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 8.0, end: 28.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Feuer-Partikel (für Streak)
    _fireController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_updateFireParticles);

    // Animationen starten
    _iconScaleController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _contentSlideController.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _buttonSlideController.forward();
    });

    // Konfetti bei Belohnungen und Achievements
    if (widget.type == StudentNotificationType.rewardUnlocked ||
        widget.type == StudentNotificationType.achievementUnlocked ||
        widget.type == StudentNotificationType.avatarUnlocked) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _confettiController.play();
      });
    }

    // Feuer bei Streak-Meilensteinen
    if (widget.type == StudentNotificationType.streakMilestone) {
      _initFireParticles();
      _fireController.repeat();
    }

    HapticFeedback.heavyImpact();
  }

  void _initFireParticles() {
    for (int i = 0; i < 20; i++) {
      _fireParticles.add(_FireParticle(random: _random));
    }
  }

  void _updateFireParticles() {
    if (!mounted) return;
    setState(() {
      for (final p in _fireParticles) {
        p.update();
        if (p.isDead) p.reset(_random);
      }
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _iconScaleController.dispose();
    _pulseController.dispose();
    _contentSlideController.dispose();
    _buttonSlideController.dispose();
    _glowController.dispose();
    _fireController.dispose();
    super.dispose();
  }

  // ── Config pro Typ ─────────────────────────────────────────────────────────

  _NotificationConfig get _config {
    switch (widget.type) {
      case StudentNotificationType.rewardUnlocked:
        final isAvatar = widget.reward?.avatarUnlockId != null;
        return _NotificationConfig(
          gradientColors: [const Color(0xFF7C4DFF), const Color(0xFF651FFF)],
          glowColor: const Color(0xFF7C4DFF),
          emoji: isAvatar ? '🎭' : '🎁',
          title: isAvatar ? 'Avatar freigeschaltet!' : 'Neue Belohnung!',
          subtitle: widget.reward?.title ?? 'Eine Belohnung wartet auf dich',
          detail: widget.reward?.reward,
          buttonLabel: '🎁 Zur Belohnung',
          showButton: widget.onGoToRewards != null,
        );

      case StudentNotificationType.achievementUnlocked:
        return _NotificationConfig(
          gradientColors: [const Color(0xFFFF8F00), const Color(0xFFFF6F00)],
          glowColor: const Color(0xFFFFB300),
          emoji: '🏆',
          title: 'Achievement!',
          subtitle: widget.reward?.title ?? 'Ziel erreicht!',
          detail: widget.reward?.description,
          buttonLabel: '🏆 Alle Achievements',
          showButton: widget.onGoToRewards != null,
        );

      case StudentNotificationType.avatarUnlocked:
        return _NotificationConfig(
          gradientColors: [const Color(0xFF00BFA5), const Color(0xFF00897B)],
          glowColor: const Color(0xFF1DE9B6),
          emoji: '🎭',
          title: 'Neuer Avatar!',
          subtitle: widget.reward?.title ?? 'Neuer Avatar freigeschaltet!',
          detail: 'Schau dir deinen neuen Avatar an!',
          buttonLabel: '🎭 Avatar anpassen',
          showButton: widget.onGoToRewards != null,
        );

      case StudentNotificationType.streakMilestone:
        return _NotificationConfig(
          gradientColors: [const Color(0xFFE64A19), const Color(0xFFBF360C)],
          glowColor: const Color(0xFFFF6D00),
          emoji: '🔥',
          title: 'Streak!',
          subtitle: widget.reward?.title ?? 'Streak-Meilenstein erreicht!',
          detail: widget.reward?.description,
          buttonLabel: '',
          showButton: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Feuer-Partikel (nur bei Streak) ──────────────────────────────
          if (widget.type == StudentNotificationType.streakMilestone)
            ..._fireParticles.map(
              (p) => Positioned(
                left: screenSize.width * 0.5 + p.x,
                top: screenSize.height * 0.4 + p.y,
                child: Opacity(
                  opacity: p.opacity,
                  child: Text('🔥', style: TextStyle(fontSize: p.size)),
                ),
              ),
            ),

          // ── Konfetti ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 30,
              gravity: 0.3,
              colors: [
                cfg.gradientColors[0],
                cfg.gradientColors[1],
                Colors.white,
                Colors.yellow,
                Colors.pink,
              ],
            ),
          ),

          // ── Haupt-Card ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: cfg.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: cfg.glowColor.withOpacity(0.5),
                    blurRadius: 40,
                    spreadRadius: 4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Animiertes Icon ─────────────────────────────────────
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _iconScaleController,
                        _pulseController,
                        _glowController,
                      ]),
                      builder: (context, _) {
                        return Transform.scale(
                          scale: _iconScale.value * _pulse.value,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.4),
                                  blurRadius: _glow.value,
                                  spreadRadius: _glow.value * 0.3,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                cfg.emoji,
                                style: const TextStyle(fontSize: 58),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // ── Titel & Subtitle ────────────────────────────────────
                    SlideTransition(
                      position: _contentSlide,
                      child: FadeTransition(
                        opacity: _contentFade,
                        child: Column(
                          children: [
                            Text(
                              cfg.title,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
                                    offset: Offset(1, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              cfg.subtitle,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.95),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (cfg.detail != null &&
                                cfg.detail!.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  cfg.detail!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white.withOpacity(0.9),
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Buttons ─────────────────────────────────────────────
                    SlideTransition(
                      position: _buttonSlide,
                      child: FadeTransition(
                        opacity: _buttonFade,
                        child: Column(
                          children: [
                            // "Zur Belohnung" Button (optional)
                            if (cfg.showButton && widget.onGoToRewards != null)
                              _buildPrimaryButton(
                                label: cfg.buttonLabel,
                                onTap: widget.onGoToRewards!,
                              ),

                            if (cfg.showButton && widget.onGoToRewards != null)
                              const SizedBox(height: 12),

                            // "Okay / Schließen" Button
                            _buildSecondaryButton(
                              label: cfg.showButton ? 'Später' : '🎉 Super!',
                              onTap: widget.onDismiss,
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
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _config.gradientColors[0],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ============================================================================
// NOTIFICATION CONFIG HELPER
// ============================================================================

class _NotificationConfig {
  final List<Color> gradientColors;
  final Color glowColor;
  final String emoji;
  final String title;
  final String subtitle;
  final String? detail;
  final String buttonLabel;
  final bool showButton;

  const _NotificationConfig({
    required this.gradientColors,
    required this.glowColor,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.detail,
    required this.buttonLabel,
    required this.showButton,
  });
}

// ============================================================================
// FEUER-PARTIKEL (für Streak-Animation)
// ============================================================================

class _FireParticle {
  double x;
  double y;
  double vx;
  double vy;
  double opacity;
  double size;
  bool isDead = false;

  _FireParticle({required Random random})
    : x = 0,
      y = 0,
      vx = 0,
      vy = 0,
      opacity = 1,
      size = 16 {
    reset(random);
  }

  void reset(Random random) {
    x = (random.nextDouble() - 0.5) * 160;
    y = random.nextDouble() * 40;
    vx = (random.nextDouble() - 0.5) * 2;
    vy = -(random.nextDouble() * 3 + 1);
    opacity = 0.8 + random.nextDouble() * 0.2;
    size = 12 + random.nextDouble() * 16;
    isDead = false;
  }

  void update() {
    x += vx;
    y += vy;
    opacity -= 0.025;
    size *= 0.97;
    if (opacity <= 0 || size < 4) isDead = true;
  }
}

// ============================================================================
// HELPER: Zeigt Popups für eine Liste von freigeschalteten Rewards
//
// Ruft das Popup für jede Belohnung der Reihe nach auf.
// Kinder sehen so kein "overload" – ein Popup nach dem anderen.
// ============================================================================

Future<void> showRewardNotifications(
  BuildContext context, {
  required List<RewardModel> rewards,
  VoidCallback? onGoToRewards,
}) async {
  for (final reward in rewards) {
    if (!context.mounted) return;

    final type = _typeForReward(reward);
    await StudentNotificationPopup.show(
      context,
      type: type,
      reward: reward,
      onGoToRewards: onGoToRewards,
    );
  }
}

StudentNotificationType _typeForReward(RewardModel reward) {
  if (reward.avatarUnlockId != null) {
    return StudentNotificationType.avatarUnlocked;
  }
  if (reward.trigger == RewardTrigger.streak) {
    return StudentNotificationType.streakMilestone;
  }
  if (reward.type == RewardType.system) {
    return StudentNotificationType.achievementUnlocked;
  }
  return StudentNotificationType.rewardUnlocked;
}
