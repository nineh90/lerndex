import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/features/rewards/presentation/widgets/achievements.dart';

// ============================================================================
// EARLY LEARNER REWARDS SCREEN – Klasse 1–2
//
// Kindgerechte Version der Belohnungsseite:
// • Riesige Emojis statt Icons
// • Bunte Kacheln in 2-er Grid
// • Kein Tab-System – stattdessen einfaches Scrollen
// • TTS-Unterstützung beim Antippen
// • Zwei Sektionen: 🎁 Geschenke & 🏆 Auszeichnungen
// ============================================================================

class EarlyLearnerRewardsScreen extends ConsumerWidget {
  const EarlyLearnerRewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChild = ref.watch(activeChildProvider);
    final user = ref.watch(authStateChangesProvider).value;

    if (activeChild == null || user == null) {
      return const Center(child: Text('🤔', style: TextStyle(fontSize: 64)));
    }

    final rewardsStream = ref
        .watch(rewardServiceProvider)
        .getRewardsStream(userId: user.uid, childId: activeChild.id);

    return StreamBuilder<List<RewardModel>>(
      stream: rewardsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Text('⏳', style: TextStyle(fontSize: 56)));
        }

        final allRewards = snapshot.data ?? [];
        final parentRewards = allRewards
            .where((r) => r.type == RewardType.parent)
            .toList();
        final approvedRewards = parentRewards
            .where((r) => r.status == RewardStatus.approved)
            .toList();
        final claimedRewards = parentRewards
            .where((r) => r.status == RewardStatus.claimed)
            .toList();
        final systemRewards = allRewards
            .where((r) => r.type == RewardType.system)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────
              _SectionHeader(emoji: '🎁', label: 'Meine Geschenke'),
              const SizedBox(height: 12),

              // ── Verfügbare Belohnungen ──────────────────────────────
              if (approvedRewards.isEmpty)
                _EmptyCard(
                  emoji: '🎀',
                  text: 'Lern weiter für Geschenke!',
                  color: const Color(0xFFEC407A),
                  ref: ref,
                  childId: activeChild.id,
                )
              else
                _RewardGrid(
                  rewards: approvedRewards,
                  userId: user.uid,
                  childId: activeChild.id,
                  ref: ref,
                  isAvailable: true,
                ),

              if (claimedRewards.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionHeader(emoji: '✅', label: 'Schon geholt'),
                const SizedBox(height: 12),
                _RewardGrid(
                  rewards: claimedRewards,
                  userId: user.uid,
                  childId: activeChild.id,
                  ref: ref,
                  isAvailable: false,
                ),
              ],

              const SizedBox(height: 24),

              // ── Auszeichnungen ──────────────────────────────────────
              _SectionHeader(emoji: '🏆', label: 'Meine Pokale'),
              const SizedBox(height: 12),

              _AchievementPreview(
                systemRewards: systemRewards,
                childId: activeChild.id,
                ref: ref,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String emoji;
  final String label;

  const _SectionHeader({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Color(0xFF4A3728),
          ),
        ),
      ],
    );
  }
}

// ── Empty State Card ──────────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  final String emoji;
  final String text;
  final Color color;
  final WidgetRef ref;
  final String childId;

  const _EmptyCard({
    required this.emoji,
    required this.text,
    required this.color,
    required this.ref,
    required this.childId,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        final ttsEnabled = ref.read(ttsSettingsProvider(childId));
        if (ttsEnabled) {
          ref.read(ttsControllerProvider.notifier).speak(text);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withOpacity(0.2), width: 2),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 10),
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reward Grid ───────────────────────────────────────────────────────────────

class _RewardGrid extends ConsumerWidget {
  final List<RewardModel> rewards;
  final String userId;
  final String childId;
  final WidgetRef ref;
  final bool isAvailable;

  const _RewardGrid({
    required this.rewards,
    required this.userId,
    required this.childId,
    required this.ref,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context, WidgetRef watchRef) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: rewards.length,
      itemBuilder: (context, index) => _RewardTile(
        reward: rewards[index],
        userId: userId,
        childId: childId,
        isAvailable: isAvailable,
      ),
    );
  }
}

// ── Reward Tile ───────────────────────────────────────────────────────────────

class _RewardTile extends ConsumerStatefulWidget {
  final RewardModel reward;
  final String userId;
  final String childId;
  final bool isAvailable;

  const _RewardTile({
    required this.reward,
    required this.userId,
    required this.childId,
    required this.isAvailable,
  });

  @override
  ConsumerState<_RewardTile> createState() => _RewardTileState();
}

class _RewardTileState extends ConsumerState<_RewardTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  // Wählt ein passendes Emoji für den Belohnungstitel
  String _rewardEmoji(String title) {
    final t = title.toLowerCase();
    if (t.contains('eis') || t.contains('ice')) return '🍦';
    if (t.contains('pizza')) return '🍕';
    if (t.contains('kino') || t.contains('film')) return '🎬';
    if (t.contains('spiel') || t.contains('game')) return '🎮';
    if (t.contains('ausflug') || t.contains('trip')) return '🚗';
    if (t.contains('buch') || t.contains('book')) return '📚';
    if (t.contains('süß') || t.contains('candy')) return '🍬';
    if (t.contains('schwimm')) return '🏊';
    if (t.contains('zoo')) return '🦁';
    if (t.contains('park')) return '🌳';
    if (t.contains('burger') || t.contains('mc')) return '🍔';
    if (t.contains('musik') || t.contains('musik')) return '🎵';
    return '🎁';
  }

  // Bunte Hintergrundfarben für die Kacheln
  static const _tileColors = [
    [Color(0xFFFF6B9D), Color(0xFFFF8CC8)],
    [Color(0xFF7C4DFF), Color(0xFFAB87FF)],
    [Color(0xFF00BCD4), Color(0xFF4DD0E1)],
    [Color(0xFFFF9800), Color(0xFFFFB74D)],
    [Color(0xFF4CAF50), Color(0xFF81C784)],
    [Color(0xFFE91E63), Color(0xFFF06292)],
  ];

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _bounceAnim = Tween(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    HapticFeedback.mediumImpact();
    _bounceCtrl.forward().then((_) => _bounceCtrl.reverse());

    final ttsEnabled = ref.read(ttsSettingsProvider(widget.childId));
    if (ttsEnabled) {
      ref.read(ttsControllerProvider.notifier).speak(widget.reward.title);
    }

    if (!widget.isAvailable) return;

    // Einlösen Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ClaimDialog(reward: widget.reward),
    );
    if (confirm == true && mounted) {
      try {
        await ref
            .read(rewardServiceProvider)
            .claimReward(
              userId: widget.userId,
              childId: widget.childId,
              rewardId: widget.reward.id,
            );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Fehler beim Einlösen')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        _tileColors[widget.reward.id.hashCode.abs() % _tileColors.length];
    final emoji = _rewardEmoji(widget.reward.title);
    final isClaimed = !widget.isAvailable;

    return ScaleTransition(
      scale: _bounceAnim,
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: isClaimed
                ? null
                : LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: isClaimed ? const Color(0xFFE8E8E8) : null,
            borderRadius: BorderRadius.circular(28),
            boxShadow: isClaimed
                ? []
                : [
                    BoxShadow(
                      color: colors[0].withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              // Deko-Kreis Hintergrund
              if (!isClaimed)
                Positioned(
                  right: -16,
                  top: -16,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

              // Hauptinhalt
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Riesiges Emoji
                    Text(
                      isClaimed ? '✅' : emoji,
                      style: const TextStyle(fontSize: 48),
                    ),
                    const SizedBox(height: 10),
                    // Titel
                    Text(
                      widget.reward.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isClaimed
                            ? const Color(0xFF999999)
                            : Colors.white,
                        shadows: isClaimed
                            ? []
                            : [
                                const Shadow(
                                  color: Colors.black26,
                                  blurRadius: 3,
                                ),
                              ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (widget.isAvailable) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          '✋ Holen!',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Claim Dialog ──────────────────────────────────────────────────────────────

class _ClaimDialog extends StatelessWidget {
  final RewardModel reward;

  const _ClaimDialog({required this.reward});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎁', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text(
              reward.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF333333),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Willst du das jetzt holen?',
              style: TextStyle(fontSize: 16, color: Color(0xFF666666)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '⬅️',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEC407A), Color(0xFFAB47BC)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEC407A).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text(
                        '✅',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Achievement Preview ───────────────────────────────────────────────────────

class _AchievementPreview extends StatelessWidget {
  final List<RewardModel> systemRewards;
  final String childId;
  final WidgetRef ref;

  const _AchievementPreview({
    required this.systemRewards,
    required this.childId,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    if (systemRewards.isEmpty) {
      return _EmptyCard(
        emoji: '🏅',
        text: 'Lerne fleißig und sammle Pokale!',
        color: const Color(0xFFFFB300),
        ref: ref,
        childId: childId,
      );
    }

    final unlocked = systemRewards
        .where((r) => r.status != RewardStatus.pending)
        .toList();
    final locked = systemRewards
        .where((r) => r.status == RewardStatus.pending)
        .toList();

    return Column(
      children: [
        // Fortschritt
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB300), Color(0xFFFF8C00)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB300).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${unlocked.length} von ${systemRewards.length} Pokalen!',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: systemRewards.isEmpty
                            ? 0
                            : unlocked.length / systemRewards.length,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Freigeschaltete Pokale
        if (unlocked.isNotEmpty) ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: unlocked
                .map((r) => _AchievementBadge(reward: r, isUnlocked: true))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],

        // Gesperrte Pokale (kleine Vorschau)
        if (locked.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: locked
                .take(4)
                .map((r) => _AchievementBadge(reward: r, isUnlocked: false))
                .toList(),
          ),
      ],
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  final RewardModel reward;
  final bool isUnlocked;

  const _AchievementBadge({required this.reward, required this.isUnlocked});

  String _badgeEmoji(String title) {
    final t = title.toLowerCase();
    if (t.contains('streak') || t.contains('feuer') || t.contains('tage'))
      return '🔥';
    if (t.contains('quiz') || t.contains('frage')) return '🎯';
    if (t.contains('level')) return '⭐';
    if (t.contains('xp') || t.contains('punkte')) return '⚡';
    if (t.contains('meister')) return '🏅';
    return '🏆';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: isUnlocked
            ? const Color(0xFFFFB300).withOpacity(0.15)
            : const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnlocked ? const Color(0xFFFFB300) : const Color(0xFFCCCCCC),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isUnlocked ? _badgeEmoji(reward.title) : '🔒',
            style: TextStyle(fontSize: isUnlocked ? 28 : 22),
          ),
          const SizedBox(height: 3),
          Text(
            reward.title.split(' ').first,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isUnlocked
                  ? const Color(0xFFE65100)
                  : const Color(0xFF999999),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
