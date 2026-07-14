import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';
import 'package:lerndex/src/features/student_dashboard/domain/avatar_config.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/dashboard_theme.dart';

/// 🏆 ACHIEVEMENTS SCREEN
/// Zeigt dem Schüler alle Systembelohnungen (freigeschaltet + noch nicht erreicht)
/// mit Fortschrittsanzeige. Eltern-Belohnungen werden hier NICHT angezeigt.

class AchievementsScreen extends ConsumerWidget {
  final DashboardThemeData? theme;

  const AchievementsScreen({super.key, this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChild = ref.watch(activeChildProvider);
    final user = ref.watch(authStateChangesProvider).value;

    if (activeChild == null || user == null) {
      return const Center(child: Text('Kein Kind ausgewählt'));
    }

    final rewardsStream = ref
        .watch(rewardServiceProvider)
        .getRewardsStream(userId: user.uid, childId: activeChild.id);

    return StreamBuilder<List<RewardModel>>(
      stream: rewardsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allRewards = snapshot.data ?? [];
        // Nur Systembelohnungen
        final systemRewards = allRewards
            .where((r) => r.type == RewardType.system)
            .toList();

        final unlockedCount = systemRewards
            .where((r) => r.status != RewardStatus.pending)
            .length;

        return CustomScrollView(
          slivers: [
            // ── Fortschritts-Header ──────────────────────────────────────
            SliverToBoxAdapter(
              child: _AchievementHeader(
                child: activeChild,
                unlockedCount: unlockedCount,
                totalCount: systemRewards.length,
              ),
            ),

            // ── Avatar-Showcase ──────────────────────────────────────────
            SliverToBoxAdapter(child: _AvatarShowcase(child: activeChild)),

            // ── Kategorien ───────────────────────────────────────────────
            ..._buildCategorySections(context, systemRewards, activeChild),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }

  List<Widget> _buildCategorySections(
    BuildContext context,
    List<RewardModel> rewards,
    ChildModel child,
  ) {
    final categories = [
      _AchievementCategory(
        icon: '⭐',
        title: 'Level-Achievements',
        color: const Color(0xFFFFB300),
        trigger: RewardTrigger.level,
        progressLabel: 'Level ${child.level}',
        progressValue: child.level.toDouble(),
      ),
      _AchievementCategory(
        icon: '⚡',
        title: 'XP-Meilensteine',
        color: const Color(0xFF7C4DFF),
        trigger: RewardTrigger.xp,
        progressLabel: '${child.xp} XP',
        progressValue: child.xp.toDouble(),
      ),
      _AchievementCategory(
        icon: '🔥',
        title: 'Streak-Rekorde',
        color: const Color(0xFFFF5722),
        trigger: RewardTrigger.streak,
        progressLabel: '${child.streak ?? 0} Tage',
        progressValue: (child.streak ?? 0).toDouble(),
      ),
      _AchievementCategory(
        icon: '📚',
        title: 'Quiz-Erfolge',
        color: const Color(0xFF00897B),
        trigger: RewardTrigger.quizCount,
        progressLabel: '${child.totalQuizzes ?? 0} Quizze',
        progressValue: (child.totalQuizzes ?? 0).toDouble(),
      ),
      const _AchievementCategory(
        icon: '💎',
        title: 'Spezial-Achievements',
        color: Color(0xFF1E88E5),
        trigger: RewardTrigger.perfectQuiz,
        progressLabel: '',
        progressValue: 0,
      ),
    ];

    return categories.map((category) {
      final categoryRewards =
          rewards.where((r) => r.trigger == category.trigger).toList()
            ..sort((a, b) => _sortValue(a).compareTo(_sortValue(b)));

      if (categoryRewards.isEmpty) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }

      return SliverToBoxAdapter(
        child: _CategorySection(
          category: category,
          rewards: categoryRewards,
          child: child,
        ),
      );
    }).toList();
  }

  int _sortValue(RewardModel r) {
    return r.requiredLevel ??
        r.requiredXP ??
        r.requiredStreak ??
        r.requiredQuizCount ??
        0;
  }
}

// ============================================================================
// HEADER MIT GESAMTFORTSCHRITT
// ============================================================================

class _AchievementHeader extends StatelessWidget {
  final ChildModel child;
  final int unlockedCount;
  final int totalCount;

  const _AchievementHeader({
    required this.child,
    required this.unlockedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalCount > 0 ? unlockedCount / totalCount : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Meine Achievements',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$unlockedCount von $totalCount freigeschaltet',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFFD600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Schnell-Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _HeaderStat(label: 'Level', value: '${child.level}', icon: '⭐'),
              _HeaderStat(label: 'XP', value: '${child.xp}', icon: '⚡'),
              _HeaderStat(
                label: 'Streak',
                value: '${child.streak ?? 0}🔥',
                icon: '',
              ),
              _HeaderStat(
                label: 'Quizze',
                value: '${child.totalQuizzes ?? 0}',
                icon: '📚',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final String icon;

  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$icon$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
        ),
      ],
    );
  }
}

// ============================================================================
// AVATAR-SHOWCASE
// ============================================================================

class _AvatarShowcase extends StatelessWidget {
  final ChildModel child;

  const _AvatarShowcase({required this.child});

  @override
  Widget build(BuildContext context) {
    // Nur Reward-Avatare die durch Achievements freischaltbar sind
    final rewardAvatars = kAvatars.where((a) => a.isRewardUnlock).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Text('🎭', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Text(
                  'Freischaltbare Avatare',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rewardAvatars.where((a) => child.unlockedAvatars.contains(a.id)).length}/${rewardAvatars.length}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rewardAvatars.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final avatar = rewardAvatars[index];
                final isUnlocked = child.unlockedAvatars.contains(avatar.id);
                return _AvatarChip(avatar: avatar, isUnlocked: isUnlocked);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarChip extends StatelessWidget {
  final AvatarConfig avatar;
  final bool isUnlocked;

  const _AvatarChip({required this.avatar, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUnlocked ? avatar.color : Colors.grey.shade300,
          width: isUnlocked ? 2 : 1.5,
        ),
        color: isUnlocked
            ? avatar.color.withValues(alpha: 0.08)
            : Colors.grey.shade50,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: ColorFiltered(
                colorFilter: isUnlocked
                    ? const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.multiply,
                      )
                    : const ColorFilter.matrix([
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                child: Image.asset(
                  'assets/images/${avatar.id}.webp',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    isUnlocked ? Icons.face : Icons.lock,
                    size: 32,
                    color: isUnlocked ? avatar.color : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              isUnlocked ? avatar.rarityLabel : '🔒 ${avatar.label}',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: isUnlocked ? avatar.color : Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// KATEGORIE-SEKTION
// ============================================================================

class _AchievementCategory {
  final String icon;
  final String title;
  final Color color;
  final RewardTrigger trigger;
  final String progressLabel;
  final double progressValue;

  const _AchievementCategory({
    required this.icon,
    required this.title,
    required this.color,
    required this.trigger,
    required this.progressLabel,
    required this.progressValue,
  });
}

class _CategorySection extends StatelessWidget {
  final _AchievementCategory category;
  final List<RewardModel> rewards;
  final ChildModel child;

  const _CategorySection({
    required this.category,
    required this.rewards,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final unlockedInCategory = rewards
        .where((r) => r.status != RewardStatus.pending)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kategorie-Header
          Row(
            children: [
              Text(category.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                category.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unlockedInCategory/${rewards.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: category.color,
                  ),
                ),
              ),
              if (category.progressLabel.isNotEmpty) ...[
                const Spacer(),
                Text(
                  category.progressLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Achievement-Karten
          ...rewards.map(
            (reward) => _AchievementTile(
              reward: reward,
              categoryColor: category.color,
              child: child,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ============================================================================
// ACHIEVEMENT TILE
// ============================================================================

class _AchievementTile extends StatelessWidget {
  final RewardModel reward;
  final Color categoryColor;
  final ChildModel child;

  const _AchievementTile({
    required this.reward,
    required this.categoryColor,
    required this.child,
  });

  bool get _isUnlocked => reward.status != RewardStatus.pending;
  bool get _isClaimed => reward.status == RewardStatus.claimed;

  double _getProgress() {
    if (_isUnlocked) return 1.0;
    if (reward.requiredLevel != null && reward.requiredLevel! > 0) {
      return (child.level / reward.requiredLevel!).clamp(0.0, 1.0);
    }
    if (reward.requiredXP != null && reward.requiredXP! > 0) {
      return (child.xp / reward.requiredXP!).clamp(0.0, 1.0);
    }
    if (reward.requiredStreak != null && reward.requiredStreak! > 0) {
      return ((child.streak ?? 0) / reward.requiredStreak!).clamp(0.0, 1.0);
    }
    if (reward.requiredQuizCount != null && reward.requiredQuizCount! > 0) {
      return ((child.totalQuizzes ?? 0) / reward.requiredQuizCount!).clamp(
        0.0,
        1.0,
      );
    }
    return 0.0;
  }

  String _getProgressText() {
    if (_isUnlocked) return 'Freigeschaltet! ✅';
    if (reward.requiredLevel != null) {
      return 'Level ${child.level} / ${reward.requiredLevel}';
    }
    if (reward.requiredXP != null) {
      return '${child.xp} / ${reward.requiredXP} XP';
    }
    if (reward.requiredStreak != null) {
      return '${child.streak ?? 0} / ${reward.requiredStreak} Tage';
    }
    if (reward.requiredQuizCount != null) {
      return '${child.totalQuizzes ?? 0} / ${reward.requiredQuizCount} Quizze';
    }
    return '';
  }

  String? _getAvatarHint() {
    if (reward.avatarUnlockId == null) return null;
    final avatar = kAvatars
        .where((a) => a.id == reward.avatarUnlockId)
        .firstOrNull;
    if (avatar == null) return null;
    return '🎭 Schaltet Avatar „${avatar.label}" frei';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _getProgress();
    final progressText = _getProgressText();
    final avatarHint = _getAvatarHint();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isUnlocked
              ? categoryColor.withValues(alpha: 0.4)
              : Colors.grey.shade200,
          width: _isUnlocked ? 1.5 : 1,
        ),
        color: _isUnlocked ? categoryColor.withValues(alpha: 0.05) : Colors.white,
        boxShadow: _isUnlocked
            ? [
                BoxShadow(
                  color: categoryColor.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status-Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isUnlocked
                        ? categoryColor.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                  ),
                  child: Center(
                    child: _isUnlocked
                        ? Text(
                            _isClaimed ? '✅' : '🎉',
                            style: const TextStyle(fontSize: 20),
                          )
                        : Text(
                            _getLockEmoji(),
                            style: const TextStyle(fontSize: 18),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _isUnlocked
                              ? Colors.black87
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reward.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Bonus-XP Badge
                if (reward.bonusXP != null && reward.bonusXP! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _isUnlocked
                          ? const Color(0xFF7C4DFF).withValues(alpha: 0.12)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+${reward.bonusXP} XP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _isUnlocked
                            ? const Color(0xFF7C4DFF)
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
              ],
            ),

            // Avatar-Hinweis
            if (avatarHint != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _isUnlocked
                      ? Colors.deepPurple.shade50
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  avatarHint,
                  style: TextStyle(
                    fontSize: 11,
                    color: _isUnlocked
                        ? Colors.deepPurple.shade400
                        : Colors.grey.shade400,
                  ),
                ),
              ),
            ],

            // Fortschrittsbalken (nur wenn nicht freigeschaltet oder gerade erreicht)
            if (progressText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isUnlocked
                              ? categoryColor
                              : categoryColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    progressText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _isUnlocked ? categoryColor : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getLockEmoji() {
    final progress = _getProgress();
    if (progress >= 0.75) return '🔓';
    if (progress >= 0.5) return '⏳';
    return '🔒';
  }
}
