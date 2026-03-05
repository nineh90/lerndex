import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/rewards/presentation/widgets/achievements.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/reward_service.dart';
import '../domain/reward_model.dart';
import '../domain/reward_enums.dart';
import 'widgets/reward_card.dart';
import '../../student_dashboard/presentation/widgets/dashboard_theme.dart';

/// 🎁 REWARDS SCREEN (Schüler-Sicht)
///
/// Wird immer eingebettet aufgerufen – keine eigene AppBar.
/// Das übergeordnete Dashboard liefert das [theme] für Farben.
///
/// Tab 1 – Verfügbar:    Eltern-Belohnungen die eingelöst werden können
/// Tab 2 – Eingelöst:    Bereits eingelöste Eltern-Belohnungen
/// Tab 3 – Achievements: Systembelohnungen mit Fortschrittsanzeige

class RewardsScreen extends ConsumerWidget {
  /// Theme des Dashboards – wird für Farben genutzt.
  /// Für Primary-Dashboard (Klasse 3–4) wird null übergeben → Fallback DeepPurple.
  final DashboardThemeData? theme;

  const RewardsScreen({super.key, this.theme});

  Color _primary(BuildContext context) => theme?.primary ?? Colors.deepPurple;
  Color _background(BuildContext context) =>
      theme?.background ?? const Color(0xFFF5F3FF);
  Color _onSurface(BuildContext context) =>
      theme?.onSurface ?? const Color(0xFF212121);
  Color _onPrimary(BuildContext context) => theme?.onPrimary ?? Colors.white;

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

    final primary = _primary(context);
    final background = _background(context);
    final onSurface = _onSurface(context);
    final onPrimary = _onPrimary(context);

    return StreamBuilder<List<RewardModel>>(
      stream: rewardsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: primary));
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Fehler: ${snapshot.error}'),
              ],
            ),
          );
        }

        final allRewards = snapshot.data ?? [];

        // Eltern-Belohnungen
        final parentRewards = allRewards
            .where((r) => r.type == RewardType.parent)
            .toList();
        final approvedRewards = parentRewards
            .where((r) => r.status == RewardStatus.approved)
            .toList();
        final claimedRewards = parentRewards
            .where((r) => r.status == RewardStatus.claimed)
            .toList();

        // Achievements (Systembelohnungen)
        final systemRewards = allRewards
            .where((r) => r.type == RewardType.system)
            .toList();
        final unlockedCount = systemRewards
            .where((r) => r.status != RewardStatus.pending)
            .length;

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              // ── Tab-Bar in Primary-Farbe ──────────────────────────────
              Container(
                color: primary,
                child: TabBar(
                  indicatorColor: onPrimary,
                  indicatorWeight: 3,
                  labelColor: onPrimary,
                  unselectedLabelColor: onPrimary.withOpacity(0.55),
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.card_giftcard, size: 18),
                      text: approvedRewards.isNotEmpty
                          ? 'Verfügbar (${approvedRewards.length})'
                          : 'Verfügbar',
                    ),
                    const Tab(
                      icon: Icon(Icons.history, size: 18),
                      text: 'Eingelöst',
                    ),
                    Tab(
                      icon: const Icon(Icons.emoji_events, size: 18),
                      text: '$unlockedCount/${systemRewards.length} 🏆',
                    ),
                  ],
                ),
              ),

              // ── Tab Views in Background-Farbe ─────────────────────────
              Expanded(
                child: Container(
                  color: background,
                  child: TabBarView(
                    children: [
                      _buildParentRewardTab(
                        context,
                        ref,
                        approvedRewards,
                        user.uid,
                        activeChild.id,
                        isAvailable: true,
                        onSurface: onSurface,
                        primary: primary,
                        onPrimary: onPrimary,
                      ),
                      _buildParentRewardTab(
                        context,
                        ref,
                        claimedRewards,
                        user.uid,
                        activeChild.id,
                        isAvailable: false,
                        onSurface: onSurface,
                        primary: primary,
                        onPrimary: onPrimary,
                      ),
                      AchievementsScreen(theme: theme),
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

  Widget _buildParentRewardTab(
    BuildContext context,
    WidgetRef ref,
    List<RewardModel> rewards,
    String userId,
    String childId, {
    required bool isAvailable,
    required Color onSurface,
    required Color primary,
    required Color onPrimary,
  }) {
    if (rewards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAvailable
                  ? Icons.card_giftcard_outlined
                  : Icons.check_circle_outline,
              size: 72,
              color: onSurface.withOpacity(0.2),
            ),
            const SizedBox(height: 20),
            Text(
              isAvailable
                  ? 'Keine Belohnungen verfügbar'
                  : 'Noch nichts eingelöst',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: onSurface.withOpacity(0.5),
              ),
            ),
            if (isAvailable) ...[
              const SizedBox(height: 8),
              Text(
                'Schau ins Achievements-Tab 🏆',
                style: TextStyle(
                  fontSize: 13,
                  color: onSurface.withOpacity(0.35),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rewards.length,
      itemBuilder: (context, index) {
        final reward = rewards[index];
        return RewardCard(
          reward: reward,
          onClaim: isAvailable
              ? () async {
                  await _claimReward(
                    context,
                    ref,
                    userId,
                    childId,
                    reward,
                    primary,
                    onPrimary,
                  );
                }
              : null,
        );
      },
    );
  }

  Future<void> _claimReward(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String childId,
    RewardModel reward,
    Color primary,
    Color onPrimary,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🎁 Belohnung einlösen?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reward.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.card_giftcard, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reward.reward,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Möchtest du diese Belohnung jetzt einlösen?\nDeine Eltern werden benachrichtigt.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: onPrimary,
            ),
            child: const Text('Einlösen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(rewardServiceProvider)
            .claimReward(userId: userId, childId: childId, rewardId: reward.id);

        if (reward.avatarUnlockId != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('children')
              .doc(childId)
              .update({
                'unlockedAvatars': FieldValue.arrayUnion([
                  reward.avatarUnlockId,
                ]),
              });

          if (context.mounted) {
            final current = ref.read(activeChildProvider);
            if (current != null) {
              final updated = List<String>.from(current.unlockedAvatars)
                ..add(reward.avatarUnlockId!);
              ref
                  .read(activeChildProvider.notifier)
                  .update(current.copyWith(unlockedAvatars: updated));
            }
          }
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reward.avatarUnlockId != null
                    ? '🎭 Avatar freigeschaltet!'
                    : '🎉 ${reward.title} eingelöst!',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
