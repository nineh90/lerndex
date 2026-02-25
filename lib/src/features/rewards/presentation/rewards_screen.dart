import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/reward_service.dart';
import '../domain/reward_model.dart';
import '../domain/reward_enums.dart';

/// 🎁 VOLLSTÄNDIGER REWARDS SCREEN
/// Ersetzt die Stub-Version in rewards_screen.dart

class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChild = ref.watch(activeChildProvider);
    final user = ref.watch(authStateChangesProvider).value;

    if (activeChild == null || user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Meine Belohnungen')),
        body: const Center(child: Text('Kein Kind ausgewählt')),
      );
    }

    final rewardsStream = ref
        .watch(rewardServiceProvider)
        .getRewardsStream(userId: user.uid, childId: activeChild.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎁 Meine Belohnungen'),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<RewardModel>>(
        stream: rewardsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Fehler: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Zurück'),
                  ),
                ],
              ),
            );
          }

          final allRewards = snapshot.data ?? [];
          final approvedRewards = allRewards
              .where((r) => r.status == RewardStatus.approved)
              .toList();
          final claimedRewards = allRewards
              .where((r) => r.status == RewardStatus.claimed)
              .toList();

          if (allRewards.isEmpty) {
            return _buildEmptyState(context);
          }

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                // Stats Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.amber.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatChip(
                        icon: Icons.card_giftcard,
                        label: 'Verfügbar',
                        value: approvedRewards.length.toString(),
                        color: Colors.green,
                      ),
                      _StatChip(
                        icon: Icons.check_circle,
                        label: 'Eingelöst',
                        value: claimedRewards.length.toString(),
                        color: Colors.blue,
                      ),
                      _StatChip(
                        icon: Icons.stars,
                        label: 'Gesamt',
                        value: allRewards.length.toString(),
                        color: Colors.amber,
                      ),
                    ],
                  ),
                ),

                // Tabs
                Container(
                  color: Colors.white,
                  child: const TabBar(
                    labelColor: Colors.amber,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.amber,
                    tabs: [
                      Tab(icon: Icon(Icons.card_giftcard), text: 'Verfügbar'),
                      Tab(icon: Icon(Icons.history), text: 'Eingelöst'),
                    ],
                  ),
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    children: [
                      // Verfügbare Belohnungen
                      _buildRewardList(
                        context,
                        ref,
                        approvedRewards,
                        user.uid,
                        activeChild.id,
                        isAvailable: true,
                      ),

                      // Eingelöste Belohnungen
                      _buildRewardList(
                        context,
                        ref,
                        claimedRewards,
                        user.uid,
                        activeChild.id,
                        isAvailable: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.card_giftcard, size: 100, color: Colors.grey.shade300),
          const SizedBox(height: 24),
          Text(
            'Noch keine Belohnungen',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mach Quizze und erreiche Level-Ups\num Belohnungen zu verdienen!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Zurück zum Dashboard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardList(
    BuildContext context,
    WidgetRef ref,
    List<RewardModel> rewards,
    String userId,
    String childId, {
    required bool isAvailable,
  }) {
    if (rewards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAvailable ? Icons.card_giftcard : Icons.check_circle,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              isAvailable
                  ? 'Keine verfügbaren Belohnungen'
                  : 'Noch keine Belohnungen eingelöst',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rewards.length,
      itemBuilder: (context, index) {
        final reward = rewards[index];
        return _RewardCard(
          reward: reward,
          onClaim: isAvailable
              ? () async {
                  await _claimReward(context, ref, userId, childId, reward);
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
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, color: Colors.amber),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
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

        // Avatar freischalten falls avatarUnlockId gesetzt ist
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

          // Auch den lokalen Provider sofort aktualisieren
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

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _RewardCard extends StatelessWidget {
  final RewardModel reward;
  final VoidCallback? onClaim;

  const _RewardCard({required this.reward, this.onClaim});

  @override
  Widget build(BuildContext context) {
    final isClaimed = reward.status == RewardStatus.claimed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isClaimed ? 1 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isClaimed ? Colors.grey.shade200 : Colors.amber.shade200,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(reward.statusEmoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isClaimed ? Colors.grey : Colors.black,
                        ),
                      ),
                      if (reward.description.isNotEmpty)
                        Text(
                          reward.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isClaimed)
                  const Icon(Icons.check_circle, color: Colors.green, size: 32),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isClaimed ? Colors.grey.shade100 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.card_giftcard,
                    color: isClaimed ? Colors.grey : Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reward.reward,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isClaimed ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onClaim != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onClaim,
                  icon: const Icon(Icons.redeem),
                  label: const Text('Belohnung einlösen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
            if (isClaimed && reward.claimedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Eingelöst am ${_formatDate(reward.claimedAt!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }
}
