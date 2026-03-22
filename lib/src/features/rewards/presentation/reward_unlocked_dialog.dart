import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../domain/reward_model.dart';

// ============================================================================
// REWARD UNLOCKED DIALOG — Lerndex Design v2
//
// Kompakt, kein Scrollen, Button immer sichtbar.
// Lerndex-Lila Farbwelt, klares Layout.
// ============================================================================

class RewardUnlockedDialog extends StatefulWidget {
  final List<RewardModel> rewards;
  final bool isLevelUp;
  final int? newLevel;

  const RewardUnlockedDialog({
    super.key,
    required this.rewards,
    this.isLevelUp = false,
    this.newLevel,
  });

  @override
  State<RewardUnlockedDialog> createState() => _RewardUnlockedDialogState();
}

class _RewardUnlockedDialogState extends State<RewardUnlockedDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late ConfettiController _confettiController;

  // Lerndex Lila Palette
  static const _purple = Color(0xFF6B21A8);
  static const _purpleLight = Color(0xFF9333EA);
  static const _purpleDark = Color(0xFF4C1D95);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );

    _scaleAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    _controller.forward();
    if (widget.isLevelUp) _confettiController.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // ── Haupt-Card ──────────────────────────────────────────────────
          FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_purpleDark, _purple, _purpleLight],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _purple.withOpacity(0.5),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ─────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 36, 28, 0),
                      child: Column(
                        children: [
                          // Icon-Kreis
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                widget.isLevelUp ? '🏆' : '🎁',
                                style: const TextStyle(fontSize: 40),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Titel
                          Text(
                            widget.isLevelUp ? 'Level Up!' : 'Belohnung!',
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),

                          // Level-Badge
                          if (widget.isLevelUp && widget.newLevel != null) ...[
                            const SizedBox(height: 10),
                            _LevelBadge(level: widget.newLevel!),
                          ],
                        ],
                      ),
                    ),

                    // ── Divider ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      child: Divider(
                        color: Colors.white.withOpacity(0.25),
                        height: 1,
                      ),
                    ),

                    // ── Rewards (kompakt, max 2) ───────────────────────────
                    if (widget.rewards.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: widget.rewards
                              .take(2)
                              .map((r) => _CompactRewardRow(reward: r))
                              .toList(),
                        ),
                      ),

                    // ── Button ─────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _purple,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            widget.isLevelUp ? 'Super! 🎉' : 'Okay! 👍',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Confetti ────────────────────────────────────────────────────
          if (widget.isLevelUp)
            Positioned(
              top: 0,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirection: 3.14 / 2,
                maxBlastForce: 18,
                minBlastForce: 8,
                emissionFrequency: 0.06,
                numberOfParticles: 18,
                gravity: 0.35,
                colors: const [
                  Colors.amber,
                  Colors.white,
                  Color(0xFFE9D5FF),
                  Color(0xFFC084FC),
                  Colors.pink,
                  Colors.cyan,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Level Badge ───────────────────────────────────────────────────────────────

class _LevelBadge extends StatelessWidget {
  final int level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Level',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$level',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF6B21A8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kompakte Reward-Zeile ─────────────────────────────────────────────────────

class _CompactRewardRow extends StatelessWidget {
  final RewardModel reward;
  const _CompactRewardRow({required this.reward});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Text(reward.statusEmoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reward.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (reward.reward.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    reward.reward,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (reward.bonusXP != null && reward.bonusXP! > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade600,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '+${reward.bonusXP} XP',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
