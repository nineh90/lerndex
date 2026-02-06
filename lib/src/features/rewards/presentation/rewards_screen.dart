import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/reward_model.dart';
import '../data/reward_repository.dart';
import '../../auth/presentation/active_child_provider.dart';

/// Screen für Kinder: Zeigt alle Belohnungen an
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(activeChildProvider);
    if (child == null) return const SizedBox();

    final rewardsAsync = ref.watch(childRewardsProvider(child.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Belohnungen'),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
      ),
      body: rewardsAsync.when(
        data: (rewards) {
          if (rewards.isEmpty) {
            return _buildEmptyState();
          }

          // Gruppiere nach Status
          final unlocked = rewards.where((r) => r.isUnlocked && !r.isRedeemed).toList();
          final redeemed = rewards.where((r) => r.isRedeemed).toList();
          final locked = rewards.where((r) => !r.isUnlocked).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Freigeschaltete Belohnungen
                if (unlocked.isNotEmpty) ...[
                  _buildSectionHeader('🎁 Verfügbar', unlocked.length),
                  const SizedBox(height: 12),
                  ...unlocked.map((reward) => _RewardCard(
                    reward: reward,
                    status: RewardStatus.unlocked,
                    onRedeem: () => _redeemReward(context, ref, child.id, reward),
                  )),
                  const SizedBox(height: 24),
                ],

                // Eingelöste Belohnungen
                if (redeemed.isNotEmpty) ...[
                  _buildSectionHeader('✅ Eingelöst', redeemed.length),
                  const SizedBox(height: 12),
                  ...redeemed.map((reward) => _RewardCard(
                    reward: reward,
                    status: RewardStatus.redeemed,
                  )),
                  const SizedBox(height: 24),
                ],

                // Noch gesperrte Belohnungen
                if (locked.isNotEmpty) ...[
                  _buildSectionHeader('🔒 Noch nicht verdient', locked.length),
                  const SizedBox(height: 12),
                  ...locked.map((reward) => _RewardCard(
                    reward: reward,
                    status: RewardStatus.locked,
                  )),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Fehler: $e')),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.card_giftcard, size: 100, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            'Noch keine Belohnungen',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Deine Eltern können Belohnungen für dich einrichten!',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  void _redeemReward(BuildContext context, WidgetRef ref, String childId, Reward reward) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${reward.icon} ${reward.title}'),
        content: Text('Möchtest du diese Belohnung jetzt einlösen?\n\n"${reward.description}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(rewardRepositoryProvider).redeemReward(childId, reward.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🎉 Belohnung eingelöst! Frag deine Eltern!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Einlösen'),
          ),
        ],
      ),
    );
  }
}

enum RewardStatus { locked, unlocked, redeemed }

class _RewardCard extends StatelessWidget {
  final Reward reward;
  final RewardStatus status;
  final VoidCallback? onRedeem;

  const _RewardCard({
    required this.reward,
    required this.status,
    this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: status == RewardStatus.unlocked
              ? LinearGradient(
            colors: [Colors.amber.shade50, Colors.amber.shade100],
          )
              : null,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                reward.icon,
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
          title: Text(
            reward.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: status == RewardStatus.locked ? Colors.grey : Colors.black,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                reward.description,
                style: TextStyle(
                  color: status == RewardStatus.locked ? Colors.grey : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(),
                  ),
                ),
              ),
            ],
          ),
          trailing: status == RewardStatus.unlocked
              ? ElevatedButton(
            onPressed: onRedeem,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('Einlösen'),
          )
              : Icon(
            status == RewardStatus.locked ? Icons.lock : Icons.check_circle,
            color: _getStatusColor(),
            size: 32,
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case RewardStatus.locked:
        return Colors.grey;
      case RewardStatus.unlocked:
        return Colors.amber;
      case RewardStatus.redeemed:
        return Colors.green;
    }
  }

  String _getStatusText() {
    switch (status) {
      case RewardStatus.locked:
        return RewardTrigger.getDescription(reward.trigger, reward.triggerValue);
      case RewardStatus.unlocked:
        return 'Bereit zum Einlösen!';
      case RewardStatus.redeemed:
        return 'Eingelöst';
    }
  }
}