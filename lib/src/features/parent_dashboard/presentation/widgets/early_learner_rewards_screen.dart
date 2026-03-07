import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';

// ============================================================================
// EARLY LEARNER REWARDS SCREEN – Klasse 1–2 (6–8 Jahre)
//
// • Eltern-Geschenke: bunte Kacheln mit kindgerechtem Fortschritt
//   – Verfügbar:  großes Emoji + "✋ Holen!"
//   – Gesperrt:   Emoji + Fortschrittsbalken mit aktuellem Wert / Zielwert
//   – Eingelöst:  ausgegraut + ✅
// • Systembelohnungen: Kategorien mit großen Emoji-Kacheln + Fortschritt
//   – Freigeschaltet: lila gefüllt
//   – Gesperrt:       hell mit 🔒 + kleiner Fortschrittsbalken
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
        final c = activeChild;

        bool conditionMet(RewardModel r) {
          switch (r.trigger) {
            case RewardTrigger.level:
              return r.requiredLevel != null && c.level >= r.requiredLevel!;
            case RewardTrigger.xp:
              if (r.requiredXP == null) return false;
              final xpTarget = (r.baselineXP ?? 0) + r.requiredXP!;
              return c.xp >= xpTarget;
            case RewardTrigger.stars:
              return r.requiredStars != null && c.stars >= r.requiredStars!;
            case RewardTrigger.streak:
              return r.requiredStreak != null &&
                  (c.streak ?? 0) >= r.requiredStreak!;
            case RewardTrigger.quizCount:
              return r.requiredQuizCount != null &&
                  (c.totalQuizzes ?? 0) >= r.requiredQuizCount!;
            case RewardTrigger.manual:
              return true;
            default:
              return false;
          }
        }

        final approvedRewards = allRewards
            .where(
              (r) =>
                  r.type == RewardType.parent &&
                  r.status == RewardStatus.approved,
            )
            .toList();

        // Pending aber Bedingung bereits erfüllt → als verfügbar zeigen
        final pendingButMet = allRewards
            .where(
              (r) =>
                  r.type == RewardType.parent &&
                  r.status == RewardStatus.pending &&
                  conditionMet(r),
            )
            .toList();

        // Pending und noch nicht erfüllt → wirklich gesperrt
        final pendingParentRewards = allRewards
            .where(
              (r) =>
                  r.type == RewardType.parent &&
                  r.status == RewardStatus.pending &&
                  !conditionMet(r),
            )
            .toList();

        final claimedRewards = allRewards
            .where(
              (r) =>
                  r.type == RewardType.parent &&
                  r.status == RewardStatus.claimed,
            )
            .toList();
        final systemRewards = allRewards
            .where((r) => r.type == RewardType.system)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Einlösbare Eltern-Geschenke ─────────────────────────
              if (approvedRewards.isNotEmpty || pendingButMet.isNotEmpty) ...[
                _ParentRewardGrid(
                  rewards: [...approvedRewards, ...pendingButMet],
                  userId: user.uid,
                  childId: activeChild.id,
                  child: activeChild,
                  mode: _TileMode.available,
                ),
                const SizedBox(height: 24),
              ],

              // ── Gesperrte Eltern-Geschenke (mit Fortschritt) ────────
              if (pendingParentRewards.isNotEmpty) ...[
                _ParentRewardGrid(
                  rewards: pendingParentRewards,
                  userId: user.uid,
                  childId: activeChild.id,
                  child: activeChild,
                  mode: _TileMode.locked,
                ),
                const SizedBox(height: 24),
              ],

              // ── Systembelohnungen nach Kategorie ────────────────────
              if (systemRewards.isNotEmpty) ...[
                _SystemAchievements(rewards: systemRewards, child: activeChild),
              ],

              // ── Eingelöst (ganz unten, dezent) ──────────────────────
              if (claimedRewards.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(color: Color(0xFFE0D8FF)),
                const SizedBox(height: 12),
                ...claimedRewards.map(
                  (r) => _ParentRewardTile(
                    reward: r,
                    userId: user.uid,
                    childId: activeChild.id,
                    child: activeChild,
                    mode: _TileMode.claimed,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Leer-Zustand ────────────────────────────────────────
              if (approvedRewards.isEmpty &&
                  pendingParentRewards.isEmpty &&
                  claimedRewards.isEmpty &&
                  systemRewards.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Column(
                      children: const [
                        Text('🎁', style: TextStyle(fontSize: 80)),
                        SizedBox(height: 16),
                        Text(
                          'Lern weiter!\nBald gibt es Geschenke!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF37205A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _TileMode { available, locked, claimed }

// ── Parent Reward Grid ────────────────────────────────────────────────────────

class _ParentRewardGrid extends StatelessWidget {
  final List<RewardModel> rewards;
  final String userId;
  final String childId;
  final ChildModel child;
  final _TileMode mode;

  const _ParentRewardGrid({
    required this.rewards,
    required this.userId,
    required this.childId,
    required this.child,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: mode == _TileMode.locked ? 0.68 : 0.78,
      ),
      itemCount: rewards.length,
      itemBuilder: (context, i) => _ParentRewardTile(
        reward: rewards[i],
        userId: userId,
        childId: childId,
        child: child,
        mode: mode,
      ),
    );
  }
}

// ── Parent Reward Tile ────────────────────────────────────────────────────────

class _ParentRewardTile extends ConsumerStatefulWidget {
  final RewardModel reward;
  final String userId;
  final String childId;
  final ChildModel child;
  final _TileMode mode;

  const _ParentRewardTile({
    required this.reward,
    required this.userId,
    required this.childId,
    required this.child,
    required this.mode,
  });

  @override
  ConsumerState<_ParentRewardTile> createState() => _ParentRewardTileState();
}

class _ParentRewardTileState extends ConsumerState<_ParentRewardTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounce;

  String _rewardEmoji(String title) {
    final t = title.toLowerCase();
    if (t.contains('eis')) return '🍦';
    if (t.contains('pizza')) return '🍕';
    if (t.contains('kino') || t.contains('film')) return '🎬';
    if (t.contains('spiel') || t.contains('game')) return '🎮';
    if (t.contains('ausflug')) return '🚗';
    if (t.contains('buch')) return '📚';
    if (t.contains('süß') || t.contains('candy')) return '🍬';
    if (t.contains('schwimm')) return '🏊';
    if (t.contains('zoo')) return '🦁';
    if (t.contains('park')) return '🌳';
    if (t.contains('burger')) return '🍔';
    if (t.contains('musik')) return '🎵';
    if (t.contains('tablet') || t.contains('handy')) return '📱';
    return '🎁';
  }

  // Aktueller Fortschrittswert des Kindes (XP relativ zur Baseline)
  double _progress() {
    final r = widget.reward;
    final c = widget.child;
    switch (r.trigger) {
      case RewardTrigger.level:
        return r.requiredLevel != null
            ? (c.level / r.requiredLevel!).clamp(0.0, 1.0)
            : 0;
      case RewardTrigger.xp:
        if (r.requiredXP == null) return 0;
        final baseline = r.baselineXP ?? 0;
        final target = r.requiredXP!;
        final gained = (c.xp - baseline).clamp(0, target);
        return gained / target;
      case RewardTrigger.stars:
        return r.requiredStars != null
            ? (c.stars / r.requiredStars!).clamp(0.0, 1.0)
            : 0;
      case RewardTrigger.streak:
        return r.requiredStreak != null
            ? ((c.streak ?? 0) / r.requiredStreak!).clamp(0.0, 1.0)
            : 0;
      case RewardTrigger.quizCount:
        return r.requiredQuizCount != null
            ? ((c.totalQuizzes ?? 0) / r.requiredQuizCount!).clamp(0.0, 1.0)
            : 0;
      default:
        return 0;
    }
  }

  // Fortschrittstext: "3 / 10 ⭐" – XP relativ zur Baseline
  String _progressLabel() {
    final r = widget.reward;
    final c = widget.child;
    switch (r.trigger) {
      case RewardTrigger.level:
        return '${c.level} / ${r.requiredLevel} 🏆';
      case RewardTrigger.xp:
        final baseline = r.baselineXP ?? 0;
        final gained = (c.xp - baseline).clamp(0, r.requiredXP ?? 0);
        return '$gained / ${r.requiredXP} ⚡';
      case RewardTrigger.stars:
        return '${c.stars} / ${r.requiredStars} ⭐';
      case RewardTrigger.streak:
        return '${c.streak ?? 0} / ${r.requiredStreak} 🔥';
      case RewardTrigger.quizCount:
        return '${c.totalQuizzes ?? 0} / ${r.requiredQuizCount} 📝';
      case RewardTrigger.perfectQuiz:
        return '💯 Quiz';
      case RewardTrigger.manual:
        return '👨‍👩‍👧';
      default:
        return '';
    }
  }

  static const _gradients = [
    [Color(0xFF7C4DFF), Color(0xFFAB87FF)],
    [Color(0xFF9C27B0), Color(0xFFCE93D8)],
    [Color(0xFF5C6BC0), Color(0xFF9FA8DA)],
    [Color(0xFF00897B), Color(0xFF80CBC4)],
    [Color(0xFFEC407A), Color(0xFFF48FB1)],
    [Color(0xFF1E88E5), Color(0xFF90CAF9)],
  ];

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    HapticFeedback.mediumImpact();
    _bounce.forward().then((_) => _bounce.reverse());
    final ttsEnabled = ref.read(ttsSettingsProvider(widget.childId));
    if (ttsEnabled) {
      ref.read(ttsControllerProvider.notifier).speak(widget.reward.title);
    }
    if (widget.mode != _TileMode.available) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ClaimDialog(reward: widget.reward),
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
      } catch (_) {
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
    // Eingelöste Belohnungen als schmale Zeile rendern
    if (widget.mode == _TileMode.claimed) {
      return _buildClaimedRow();
    }
    return _buildTile();
  }

  // ── Schmale Zeile für eingelöste Belohnungen ──────────────────────────────
  Widget _buildClaimedRow() {
    final emoji = _rewardEmoji(widget.reward.title);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD6FE), width: 1.5),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.reward.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9E9E9E),
                decoration: TextDecoration.lineThrough,
                decorationColor: Color(0xFF9E9E9E),
              ),
            ),
          ),
          const Text('✅', style: TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  // ── Bunte Kachel für verfügbar + gesperrt ─────────────────────────────────
  Widget _buildTile() {
    final grad =
        _gradients[widget.reward.id.hashCode.abs() % _gradients.length];
    final emoji = _rewardEmoji(widget.reward.title);
    final isLocked = widget.mode == _TileMode.locked;
    final progress = _progress();
    final label = _progressLabel();

    // Gesperrte Kachel: helle Variante der gleichen Farben
    final tileColors = isLocked
        ? [
            Color.lerp(grad[0], Colors.white, 0.55)!,
            Color.lerp(grad[1], Colors.white, 0.55)!,
          ]
        : grad;

    return ScaleTransition(
      scale: Tween(
        begin: 1.0,
        end: 0.93,
      ).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeInOut)),
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: tileColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: tileColors[0].withOpacity(isLocked ? 0.2 : 0.45),
                blurRadius: isLocked ? 8 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            children: [
              // Deko-Kreis oben rechts
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isLocked ? 0.06 : 0.12),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Deko-Kreis unten links
              Positioned(
                left: -12,
                bottom: -12,
                child: Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isLocked ? 0.04 : 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Haupt-Emoji (bei gesperrt mit 🔒 überlagert)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          emoji,
                          style: TextStyle(
                            fontSize: 32,
                            color: Colors.white.withOpacity(
                              isLocked ? 0.4 : 1.0,
                            ),
                          ),
                        ),
                        if (isLocked)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Text(
                              '🔒',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Titel
                    Text(
                      widget.reward.title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isLocked
                            ? const Color(0xFF37205A)
                            : Colors.white,
                        shadows: isLocked
                            ? null
                            : const [
                                Shadow(color: Colors.black26, blurRadius: 3),
                              ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 6),

                    // ── Gesperrt: Fortschrittsbalken ──────────────────
                    if (isLocked && label.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 7,
                          backgroundColor: isLocked
                              ? const Color(0xFF37205A).withOpacity(0.15)
                              : Colors.white.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isLocked
                                ? const Color(0xFF37205A).withOpacity(0.7)
                                : Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: isLocked
                              ? const Color(0xFF37205A)
                              : Colors.white.withOpacity(0.9),
                          shadows: isLocked
                              ? null
                              : const [
                                  Shadow(color: Colors.black26, blurRadius: 2),
                                ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    // ── Verfügbar: Holen-Button ────────────────────────
                    if (!isLocked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '✋ Holen!',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
                          colors: [Color(0xFF7C4DFF), Color(0xFF512DA8)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C4DFF).withOpacity(0.4),
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

// ── System Achievements – nach Kategorien ─────────────────────────────────────

class _AchievCat {
  final String emoji;
  final Color color;
  final RewardTrigger trigger;
  const _AchievCat(this.emoji, this.color, this.trigger);
}

class _SystemAchievements extends StatelessWidget {
  final List<RewardModel> rewards;
  final ChildModel child;

  const _SystemAchievements({required this.rewards, required this.child});

  static const _categories = [
    _AchievCat('🏆', Color(0xFF7C4DFF), RewardTrigger.level),
    _AchievCat('⚡', Color(0xFF3949AB), RewardTrigger.xp),
    _AchievCat('⭐', Color(0xFF8E24AA), RewardTrigger.stars),
    _AchievCat('🔥', Color(0xFFE53935), RewardTrigger.streak),
    _AchievCat('📝', Color(0xFF00897B), RewardTrigger.quizCount),
    _AchievCat('💯', Color(0xFF1E88E5), RewardTrigger.perfectQuiz),
  ];

  static bool _isConditionMet(RewardModel r, ChildModel c) {
    if (r.status != RewardStatus.pending) return true;
    switch (r.trigger) {
      case RewardTrigger.level:
        return r.requiredLevel != null && c.level >= r.requiredLevel!;
      case RewardTrigger.xp:
        return r.requiredXP != null && c.xp >= r.requiredXP!;
      case RewardTrigger.stars:
        return r.requiredStars != null && c.stars >= r.requiredStars!;
      case RewardTrigger.streak:
        return r.requiredStreak != null && (c.streak ?? 0) >= r.requiredStreak!;
      case RewardTrigger.quizCount:
        return r.requiredQuizCount != null &&
            (c.totalQuizzes ?? 0) >= r.requiredQuizCount!;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _categories.map((cat) {
        final catRewards =
            rewards.where((r) => r.trigger == cat.trigger).toList()
              ..sort((a, b) => _sortVal(a).compareTo(_sortVal(b)));

        if (catRewards.isEmpty) return const SizedBox.shrink();

        final doneCount = catRewards
            .where((r) => _isConditionMet(r, child))
            .length;
        final total = catRewards.length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Kategorie-Header ────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cat.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(cat.emoji, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: total > 0 ? doneCount / total : 0,
                              minHeight: 12,
                              backgroundColor: cat.color.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cat.color,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$doneCount von $total',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cat.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Achievement-Karten (horizontal) ────────────────────
              ...catRewards.map(
                (r) => _AchievCard(reward: r, child: child, color: cat.color),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  int _sortVal(RewardModel r) =>
      r.requiredLevel ??
      r.requiredXP ??
      r.requiredStars ??
      r.requiredStreak ??
      r.requiredQuizCount ??
      0;
}

// ── Achievement Card (horizontal) ────────────────────────────────────────────

class _AchievCard extends StatelessWidget {
  final RewardModel reward;
  final ChildModel child;
  final Color color;

  const _AchievCard({
    required this.reward,
    required this.child,
    required this.color,
  });

  bool get _isOfficiallyUnlocked => reward.status != RewardStatus.pending;

  bool get _isConditionMet {
    if (_isOfficiallyUnlocked) return true;
    final r = reward;
    final c = child;
    switch (r.trigger) {
      case RewardTrigger.level:
        return r.requiredLevel != null && c.level >= r.requiredLevel!;
      case RewardTrigger.xp:
        return r.requiredXP != null && c.xp >= r.requiredXP!;
      case RewardTrigger.stars:
        return r.requiredStars != null && c.stars >= r.requiredStars!;
      case RewardTrigger.streak:
        return r.requiredStreak != null && (c.streak ?? 0) >= r.requiredStreak!;
      case RewardTrigger.quizCount:
        return r.requiredQuizCount != null &&
            (c.totalQuizzes ?? 0) >= r.requiredQuizCount!;
      default:
        return false;
    }
  }

  String _bigEmoji() {
    // Emoji aus dem Titel extrahieren (erstes Zeichen wenn Emoji)
    final firstChar = reward.title.characters.first;
    final code = firstChar.runes.first;
    if (code > 0x1F300) return firstChar; // Ist ein Emoji
    // Fallback nach Trigger
    switch (reward.trigger) {
      case RewardTrigger.level:
        return '🏆';
      case RewardTrigger.xp:
        return '⚡';
      case RewardTrigger.stars:
        return '⭐';
      case RewardTrigger.streak:
        return '🔥';
      case RewardTrigger.quizCount:
        return '📝';
      case RewardTrigger.perfectQuiz:
        return '💯';
      default:
        return '🌟';
    }
  }

  double _progress() {
    if (_isConditionMet) return 1.0;
    final r = reward;
    final c = child;
    if (r.requiredLevel != null && r.requiredLevel! > 0)
      return (c.level / r.requiredLevel!).clamp(0.0, 1.0);
    if (r.requiredXP != null && r.requiredXP! > 0)
      return (c.xp / r.requiredXP!).clamp(0.0, 1.0);
    if (r.requiredStars != null && r.requiredStars! > 0)
      return (c.stars / r.requiredStars!).clamp(0.0, 1.0);
    if (r.requiredStreak != null && r.requiredStreak! > 0)
      return ((c.streak ?? 0) / r.requiredStreak!).clamp(0.0, 1.0);
    if (r.requiredQuizCount != null && r.requiredQuizCount! > 0)
      return ((c.totalQuizzes ?? 0) / r.requiredQuizCount!).clamp(0.0, 1.0);
    return 0.0;
  }

  String _progressLabel() {
    if (_isConditionMet) return '';
    final r = reward;
    final c = child;
    if (r.requiredLevel != null) return '${c.level} / ${r.requiredLevel} 🏆';
    if (r.requiredXP != null) return '${c.xp} / ${r.requiredXP} ⚡';
    if (r.requiredStars != null) return '${c.stars} / ${r.requiredStars} ⭐';
    if (r.requiredStreak != null)
      return '${c.streak ?? 0} / ${r.requiredStreak} 🔥';
    if (r.requiredQuizCount != null)
      return '${c.totalQuizzes ?? 0} / ${r.requiredQuizCount} 📝';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final done = _isConditionMet;
    final progress = _progress();
    final label = _progressLabel();
    final bigEmoji = _bigEmoji();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: done ? color.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: done ? color.withOpacity(0.35) : const Color(0xFFE0D8FF),
          width: done ? 2 : 1.5,
        ),
        boxShadow: done
            ? [
                BoxShadow(
                  color: color.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // ── Linke Seite: Emoji-Badge ──────────────────────────
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: done ? color.withOpacity(0.15) : const Color(0xFFF3F0FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  done ? bigEmoji : '🔒',
                  style: const TextStyle(fontSize: 30),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // ── Rechte Seite: Titel + Fortschritt ────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titel (voller Text, lesbar)
                  Text(
                    reward.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: done ? color : const Color(0xFF9E9E9E),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  if (done) ...[
                    const SizedBox(height: 4),
                    Text(
                      _isOfficiallyUnlocked
                          ? '🎉 Freigeschaltet!'
                          : '✅ Geschafft!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color.withOpacity(0.8),
                      ),
                    ),
                  ] else if (label.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: const Color(0xFFE8E0FF),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
