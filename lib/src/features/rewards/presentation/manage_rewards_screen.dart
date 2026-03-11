import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../data/reward_service.dart';
import '../domain/reward_model.dart';
import '../domain/reward_enums.dart';
import 'widgets/reward_manage_card.dart';
import 'widgets/create_reward_dialog.dart';
import 'widgets/edit_reward_dialog.dart';

/// MANAGE REWARDS SCREEN FÜR ELTERN
/// Zeigt und verwaltet ausschließlich eltern-erstellte Belohnungen (RewardType.parent).
/// System-Belohnungen (Achievements, XP, Avatare) werden im Schüler-Dashboard angezeigt.

class ManageRewardsScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const ManageRewardsScreen({super.key, required this.child});

  @override
  ConsumerState<ManageRewardsScreen> createState() =>
      _ManageRewardsScreenState();
}

class _ManageRewardsScreenState extends ConsumerState<ManageRewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Nicht angemeldet')));
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Belohnungen für ${widget.child.name}'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Alle'),
            Tab(icon: Icon(Icons.pending_actions), text: 'Aktiv'),
            Tab(icon: Icon(Icons.check_circle), text: 'Eingelöst'),
          ],
        ),
      ),
      body: StreamBuilder<List<RewardModel>>(
        stream: ref
            .watch(rewardServiceProvider)
            .getRewardsStream(userId: user.uid, childId: widget.child.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          // Nur eltern-erstellte Belohnungen – System-Achievements gehören ins Schüler-Dashboard
          final parentRewards = (snapshot.data ?? [])
              .where((r) => r.type == RewardType.parent)
              .toList();

          final activeRewards = parentRewards
              .where(
                (r) =>
                    r.status == RewardStatus.pending ||
                    r.status == RewardStatus.approved,
              )
              .toList();

          final claimedRewards = parentRewards
              .where((r) => r.status == RewardStatus.claimed)
              .toList();

          // "Alle" = aktive + noch nicht ausgehändigte claimed (parentSeen != true)
          final allRelevant = parentRewards
              .where(
                (r) => r.status != RewardStatus.claimed || r.parentSeen != true,
              )
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildRewardsList(
                allRelevant,
                user.uid,
                'Noch keine Belohnungen erstellt',
              ),
              _buildRewardsList(
                activeRewards,
                user.uid,
                'Keine aktiven Belohnungen',
              ),
              _buildRewardsList(
                claimedRewards,
                user.uid,
                'Noch keine Belohnungen eingelöst',
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRewardDialog(
          context,
          ref.watch(authStateChangesProvider).value!.uid,
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Neue Belohnung'),
      ),
    );
  }

  Widget _buildRewardsList(
    List<RewardModel> rewards,
    String userId,
    String emptyMessage,
  ) {
    if (rewards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.card_giftcard, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tippe auf „Neue Belohnung" um eine hinzuzufügen.',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              textAlign: TextAlign.center,
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
        return RewardManageCard(
          reward: reward,
          child: widget.child,
          userId: userId,
          onEdit: () => _showEditRewardDialog(context, userId, reward),
          onDelete: () => _deleteReward(context, userId, reward),
          onToggleApproval: () => _toggleApproval(userId, reward),
          onMarkSeen: () => _markRewardSeen(userId, reward),
        );
      },
    );
  }

  Future<void> _showCreateRewardDialog(
    BuildContext context,
    String userId,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) =>
          CreateRewardDialog(child: widget.child, userId: userId),
    );
  }

  Future<void> _showEditRewardDialog(
    BuildContext context,
    String userId,
    RewardModel reward,
  ) async {
    await showDialog(
      context: context,
      builder: (context) =>
          EditRewardDialog(child: widget.child, userId: userId, reward: reward),
    );
  }

  Future<void> _deleteReward(
    BuildContext context,
    String userId,
    RewardModel reward,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('Belohnung löschen?'),
          ],
        ),
        content: Text('"${reward.title}" wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('children')
            .doc(widget.child.id)
            .collection('rewards')
            .doc(reward.id)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Belohnung gelöscht')));
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

  Future<void> _markRewardSeen(String userId, RewardModel reward) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(widget.child.id)
          .collection('rewards')
          .doc(reward.id)
          .update({'parentSeen': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleApproval(String userId, RewardModel reward) async {
    try {
      final newStatus = reward.status == RewardStatus.pending
          ? RewardStatus.approved
          : RewardStatus.pending;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(widget.child.id)
          .collection('rewards')
          .doc(reward.id)
          .update({
            'status': newStatus.toFirestore(),
            if (newStatus == RewardStatus.approved)
              'approvedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == RewardStatus.approved
                  ? '✅ Belohnung freigegeben'
                  : '⏸️ Belohnung zurückgezogen',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
