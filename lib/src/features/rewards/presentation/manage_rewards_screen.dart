import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../data/reward_service.dart';
import '../domain/reward_model.dart';
import '../domain/reward_enums.dart';
import '../../student_dashboard/domain/avatar_config.dart';

/// VOLLSTÄNDIGER MANAGE REWARDS SCREEN FÜR ELTERN
/// Ermöglicht das Erstellen, Bearbeiten und Verwalten von Belohnungen

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
        backgroundColor: Colors.amber,
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
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          final allRewards = snapshot.data ?? [];
          final activeRewards = allRewards
              .where(
                (r) =>
                    r.status == RewardStatus.pending ||
                    r.status == RewardStatus.approved,
              )
              .toList();
          final claimedRewards = allRewards
              .where((r) => r.status == RewardStatus.claimed)
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildRewardsList(allRewards, user.uid, 'Keine Belohnungen'),
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
        onPressed: () => _showCreateRewardDialog(context, user.uid),
        backgroundColor: Colors.amber,
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
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rewards.length,
      itemBuilder: (context, index) {
        final reward = rewards[index];
        return _RewardManageCard(
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
    await showDialog(
      context: context,
      builder: (context) =>
          _CreateRewardDialog(child: widget.child, userId: userId),
    );
  }

  Future<void> _showEditRewardDialog(
    BuildContext context,
    String userId,
    RewardModel reward,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => _EditRewardDialog(
        child: widget.child,
        userId: userId,
        reward: reward,
      ),
    );
  }

  Future<void> _deleteReward(
    BuildContext context,
    String userId,
    RewardModel reward,
  ) async {
    final isSystem = reward.type == RewardType.system;
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${reward.title}" wird dauerhaft gelöscht.'),
            if (isSystem) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Dies ist eine System-Belohnung. Nach dem Löschen wird sie nicht automatisch wiederhergestellt.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

// ============================================================================
// REWARD CARD
// ============================================================================

class _RewardManageCard extends StatelessWidget {
  final RewardModel reward;
  final ChildModel child;
  final String userId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleApproval;
  final VoidCallback onMarkSeen;

  const _RewardManageCard({
    required this.reward,
    required this.child,
    required this.userId,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleApproval,
    required this.onMarkSeen,
  });

  @override
  Widget build(BuildContext context) {
    final isSystemReward = reward.type == RewardType.system;
    final isPending = reward.status == RewardStatus.pending;
    final isApproved = reward.status == RewardStatus.approved;
    final isClaimed = reward.status == RewardStatus.claimed;

    // Prüfe ob Trigger erfüllt ist
    final isTriggered = reward.isTriggeredBy(
      currentLevel: child.level,
      currentXP: child.xp,
      currentStars: child.stars,
      currentStreak: child.streak ?? 0,
      currentQuizCount: child.totalQuizzes ?? 0,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isClaimed
              ? Colors.grey.shade300
              : isApproved
              ? Colors.green.shade300
              : Colors.orange.shade300,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isClaimed
                  ? Colors.grey.shade100
                  : isApproved
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Text(reward.statusEmoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            isSystemReward ? Icons.auto_awesome : Icons.person,
                            size: 12,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSystemReward ? 'System' : 'Eigene',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (isTriggered && isPending) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'BEREIT!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    if (!isClaimed)
                      PopupMenuItem(
                        onTap: onEdit,
                        child: const Row(
                          children: [
                            Icon(
                              Icons.edit,
                              size: 20,
                              color: Colors.deepPurple,
                            ),
                            SizedBox(width: 8),
                            Text('Bearbeiten'),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      onTap: onDelete,
                      child: const Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Löschen', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reward.description.isNotEmpty) ...[
                  Text(
                    reward.description,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                ],

                // Belohnung
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.card_giftcard, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reward.reward,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Trigger/Bedingung
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.flag, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bedingung',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              reward.conditionText,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isTriggered)
                        const Icon(Icons.check_circle, color: Colors.green),
                    ],
                  ),
                ),

                // Status Info + Aushändigen-Button
                if (isClaimed) ...[
                  const SizedBox(height: 12),
                  if (!reward.parentSeen)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.deepPurple.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.redeem_outlined,
                                size: 16,
                                color: Colors.deepPurple.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                reward.claimedAt != null
                                    ? 'Eingelöst am ${_formatDate(reward.claimedAt!)}'
                                    : 'Vom Kind eingelöst',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.deepPurple.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: onMarkSeen,
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Belohnung ausgehändigt'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (reward.parentSeen && reward.claimedAt != null)
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ausgehändigt am ${_formatDate(reward.claimedAt!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                ],

                // Freigabe-Button
                if (!isClaimed &&
                    !isSystemReward &&
                    reward.trigger == RewardTrigger.manual) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onToggleApproval,
                      icon: Icon(isPending ? Icons.check : Icons.pause),
                      label: Text(isPending ? 'Freigeben' : 'Zurückziehen'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPending
                            ? Colors.green
                            : Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }
}

// ============================================================================
// CREATE REWARD DIALOG
// ============================================================================

class _CreateRewardDialog extends ConsumerStatefulWidget {
  final ChildModel child;
  final String userId;

  const _CreateRewardDialog({required this.child, required this.userId});

  @override
  ConsumerState<_CreateRewardDialog> createState() =>
      _CreateRewardDialogState();
}

class _CreateRewardDialogState extends ConsumerState<_CreateRewardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rewardController = TextEditingController();

  RewardTrigger _selectedTrigger = RewardTrigger.level;
  int? _triggerValue;
  bool _isAvatarReward = false; // Toggle: Text-Belohnung vs. Avatar-Belohnung
  String? _selectedAvatarId;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _rewardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎁 Neue Belohnung erstellen',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // Titel
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titel *',
                    hintText: 'z.B. Extra Spielzeit',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Bitte Titel eingeben';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Beschreibung
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    hintText: 'Was muss erreicht werden?',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // Belohnungs-Typ Toggle
                const Text(
                  'Art der Belohnung',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isAvatarReward = false;
                          _selectedAvatarId = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: !_isAvatarReward
                                ? Colors.amber.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: !_isAvatarReward
                                  ? Colors.amber
                                  : Colors.grey.shade300,
                              width: !_isAvatarReward ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.card_giftcard,
                                color: !_isAvatarReward
                                    ? Colors.amber.shade700
                                    : Colors.grey,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Eigene\nBelohnung',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: !_isAvatarReward
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: !_isAvatarReward
                                      ? Colors.amber.shade700
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isAvatarReward = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _isAvatarReward
                                ? Colors.deepPurple.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isAvatarReward
                                  ? Colors.deepPurple
                                  : Colors.grey.shade300,
                              width: _isAvatarReward ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.face,
                                color: _isAvatarReward
                                    ? Colors.deepPurple
                                    : Colors.grey,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Avatar\nfreischalten',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _isAvatarReward
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _isAvatarReward
                                      ? Colors.deepPurple
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Belohnungs-Inhalt: Text oder Avatar-Picker
                if (!_isAvatarReward)
                  TextFormField(
                    controller: _rewardController,
                    decoration: const InputDecoration(
                      labelText: 'Belohnung *',
                      hintText: 'z.B. 30 Min extra Tablet-Zeit',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.card_giftcard),
                    ),
                    validator: (value) {
                      if (!_isAvatarReward &&
                          (value == null || value.isEmpty)) {
                        return 'Bitte Belohnung eingeben';
                      }
                      return null;
                    },
                  )
                else ...[
                  // Avatar-Picker Grid
                  FormField<String>(
                    validator: (_) =>
                        _isAvatarReward && _selectedAvatarId == null
                        ? 'Bitte Avatar auswählen'
                        : null,
                    builder: (state) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Avatar auswählen *',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: kAvatars
                              .where((a) => a.isRewardUnlock)
                              .length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.82,
                              ),
                          itemBuilder: (context, index) {
                            final avatar = kAvatars
                                .where((a) => a.isRewardUnlock)
                                .toList()[index];
                            final isSelected = _selectedAvatarId == avatar.id;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedAvatarId = avatar.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? avatar.color
                                        : avatar.color.withOpacity(0.3),
                                    width: isSelected ? 3 : 1.5,
                                  ),
                                  color: isSelected
                                      ? avatar.color.withOpacity(0.1)
                                      : Colors.grey.shade50,
                                ),
                                child: Stack(
                                  children: [
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              8,
                                              10,
                                              8,
                                              4,
                                            ),
                                            child: Image.asset(
                                              'assets/images/${avatar.id}.png',
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                    Icons.face,
                                                    size: 40,
                                                    color: avatar.color,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Text(
                                            avatar.rarityLabel,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: avatar.color,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isSelected)
                                      Positioned(
                                        top: 5,
                                        right: 5,
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: avatar.color,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        if (state.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 12),
                            child: Text(
                              state.errorText!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Trigger Auswahl
                const Text(
                  'Freigabe-Bedingung',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<RewardTrigger>(
                  value: _selectedTrigger,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                  items: RewardTrigger.values
                      .where((t) => t != RewardTrigger.avatarUnlock)
                      .map((trigger) {
                        return DropdownMenuItem(
                          value: trigger,
                          child: Text(trigger.displayName),
                        );
                      })
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedTrigger = value!;
                      _triggerValue = null;
                    });
                  },
                ),
                const SizedBox(height: 12),

                // Trigger Value Input
                if (_needsTriggerValue(_selectedTrigger)) ...[
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: _getTriggerValueLabel(_selectedTrigger),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.numbers),
                      helperText: _getTriggerHelperText(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Bitte Wert eingeben';
                      }
                      final intValue = int.tryParse(value);
                      if (intValue == null || intValue <= 0) {
                        return 'Ungültiger Wert';
                      }

                      // Validierung
                      final validation = ref
                          .read(rewardServiceProvider)
                          .validateParentReward(
                            child: widget.child,
                            trigger: _selectedTrigger,
                            requiredLevel:
                                _selectedTrigger == RewardTrigger.level
                                ? intValue
                                : null,
                            requiredXP: _selectedTrigger == RewardTrigger.xp
                                ? intValue
                                : null,
                            requiredStars:
                                _selectedTrigger == RewardTrigger.stars
                                ? intValue
                                : null,
                          );

                      if (!validation.isValid) {
                        return validation.message;
                      }

                      return null;
                    },
                    onChanged: (value) {
                      _triggerValue = int.tryParse(value);
                    },
                  ),
                ],

                const SizedBox(height: 20),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isCreating
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isCreating ? null : _createReward,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Erstellen'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _needsTriggerValue(RewardTrigger trigger) {
    return trigger != RewardTrigger.manual &&
        trigger != RewardTrigger.perfectQuiz &&
        trigger != RewardTrigger.avatarUnlock;
  }

  String _getTriggerValueLabel(RewardTrigger trigger) {
    switch (trigger) {
      case RewardTrigger.level:
        return 'Erforderliches Level';
      case RewardTrigger.xp:
        return 'Erforderliche XP';
      case RewardTrigger.stars:
        return 'Erforderliche Sterne';
      case RewardTrigger.streak:
        return 'Erforderliche Streak-Tage';
      case RewardTrigger.quizCount:
        return 'Erforderliche Quiz-Anzahl';
      default:
        return 'Wert';
    }
  }

  String _getTriggerHelperText() {
    switch (_selectedTrigger) {
      case RewardTrigger.level:
        return 'Aktuell: Level ${widget.child.level}';
      case RewardTrigger.xp:
        return 'Aktuell: ${widget.child.xp} XP';
      case RewardTrigger.stars:
        return 'Aktuell: ${widget.child.stars} Sterne';
      case RewardTrigger.streak:
        return 'Aktuell: ${widget.child.streak ?? 0} Tage';
      case RewardTrigger.quizCount:
        return 'Aktuell: ${widget.child.totalQuizzes ?? 0} Quizze';
      default:
        return '';
    }
  }

  Future<void> _createReward() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final rewardData = {
        'childId': widget.child.id,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'type': 'parent',
        'trigger': _selectedTrigger.toFirestore(),
        'reward': _isAvatarReward
            ? '🎭 Avatar-Freischaltung'
            : _rewardController.text.trim(),
        'status': _selectedTrigger == RewardTrigger.manual
            ? 'approved'
            : 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': widget.userId,
        if (_isAvatarReward && _selectedAvatarId != null)
          'avatarUnlockId': _selectedAvatarId,
        if (_selectedTrigger == RewardTrigger.level)
          'requiredLevel': _triggerValue,
        if (_selectedTrigger == RewardTrigger.xp) 'requiredXP': _triggerValue,
        if (_selectedTrigger == RewardTrigger.stars)
          'requiredStars': _triggerValue,
        if (_selectedTrigger == RewardTrigger.streak)
          'requiredStreak': _triggerValue,
        if (_selectedTrigger == RewardTrigger.quizCount)
          'requiredQuizCount': _triggerValue,
        if (_selectedTrigger == RewardTrigger.manual)
          'approvedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('children')
          .doc(widget.child.id)
          .collection('rewards')
          .add(rewardData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Belohnung erstellt'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}

// ============================================================================
// EDIT REWARD DIALOG — Vollständig mit Trigger-Auswahl
// ============================================================================

class _EditRewardDialog extends ConsumerStatefulWidget {
  final ChildModel child;
  final String userId;
  final RewardModel reward;

  const _EditRewardDialog({
    required this.child,
    required this.userId,
    required this.reward,
  });

  @override
  ConsumerState<_EditRewardDialog> createState() => _EditRewardDialogState();
}

class _EditRewardDialogState extends ConsumerState<_EditRewardDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _rewardController;
  late TextEditingController _triggerValueController;

  late RewardTrigger _selectedTrigger;
  int? _triggerValue;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.reward.title);
    _descriptionController = TextEditingController(
      text: widget.reward.description,
    );
    _rewardController = TextEditingController(text: widget.reward.reward);
    _selectedTrigger = widget.reward.trigger;

    // Aktuellen Trigger-Wert aus dem Reward ermitteln
    final currentValue =
        widget.reward.requiredLevel ??
        widget.reward.requiredXP ??
        widget.reward.requiredStars ??
        widget.reward.requiredStreak ??
        widget.reward.requiredQuizCount;
    _triggerValue = currentValue;
    _triggerValueController = TextEditingController(
      text: currentValue != null ? currentValue.toString() : '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _rewardController.dispose();
    _triggerValueController.dispose();
    super.dispose();
  }

  bool _needsTriggerValue(RewardTrigger trigger) {
    return trigger != RewardTrigger.manual &&
        trigger != RewardTrigger.perfectQuiz;
  }

  String _getTriggerValueLabel(RewardTrigger trigger) {
    switch (trigger) {
      case RewardTrigger.level:
        return 'Erforderliches Level';
      case RewardTrigger.xp:
        return 'Erforderliche XP';
      case RewardTrigger.stars:
        return 'Erforderliche Sterne';
      case RewardTrigger.streak:
        return 'Erforderliche Streak-Tage';
      case RewardTrigger.quizCount:
        return 'Erforderliche Quiz-Anzahl';
      default:
        return 'Wert';
    }
  }

  String _getTriggerHelperText() {
    switch (_selectedTrigger) {
      case RewardTrigger.level:
        return 'Aktuell: Level ${widget.child.level}';
      case RewardTrigger.xp:
        return 'Aktuell: ${widget.child.xp} XP';
      case RewardTrigger.stars:
        return 'Aktuell: ${widget.child.stars} Sterne';
      case RewardTrigger.streak:
        return 'Aktuell: ${widget.child.streak ?? 0} Tage';
      case RewardTrigger.quizCount:
        return 'Aktuell: ${widget.child.totalQuizzes ?? 0} Quizze';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.amber,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Belohnung bearbeiten',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Titel
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titel *',
                    hintText: 'z.B. Extra Spielzeit',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Bitte Titel eingeben' : null,
                ),
                const SizedBox(height: 12),

                // Beschreibung
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // Belohnungstext
                TextFormField(
                  controller: _rewardController,
                  decoration: const InputDecoration(
                    labelText: 'Belohnung *',
                    hintText: 'z.B. 30 Min extra Tablet-Zeit',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.card_giftcard),
                  ),
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Bitte Belohnung eingeben'
                      : null,
                ),
                const SizedBox(height: 12),

                // Trigger-Bedingung
                const Text(
                  'Freigabe-Bedingung',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<RewardTrigger>(
                  value: _selectedTrigger,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                  items: RewardTrigger.values
                      .where((t) => t != RewardTrigger.avatarUnlock)
                      .map((trigger) {
                        return DropdownMenuItem(
                          value: trigger,
                          child: Text(trigger.displayName),
                        );
                      })
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedTrigger = value!;
                      _triggerValue = null;
                      _triggerValueController.clear();
                    });
                  },
                ),
                const SizedBox(height: 12),

                // Trigger-Wert
                if (_needsTriggerValue(_selectedTrigger)) ...[
                  TextFormField(
                    controller: _triggerValueController,
                    decoration: InputDecoration(
                      labelText: _getTriggerValueLabel(_selectedTrigger),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.numbers),
                      helperText: _getTriggerHelperText(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Bitte Wert eingeben';
                      }
                      final intValue = int.tryParse(value);
                      if (intValue == null || intValue <= 0) {
                        return 'Ungültiger Wert';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      _triggerValue = int.tryParse(value);
                    },
                  ),
                ],

                const SizedBox(height: 20),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isUpdating
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _updateReward,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isUpdating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save, size: 18),
                      label: const Text('Speichern'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateReward() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    try {
      // Trigger-Wert-Felder aufbauen
      final updateData = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'reward': _rewardController.text.trim(),
        'trigger': _selectedTrigger.toFirestore(),
        // System-Belohnungen werden nach Bearbeitung zu eigenen Belohnungen
        'type': 'parent',
        // Status auf pending zurücksetzen wenn Trigger geändert und nicht manual
        if (_selectedTrigger != RewardTrigger.manual) 'status': 'pending',
        if (_selectedTrigger == RewardTrigger.manual) 'status': 'approved',
        if (_selectedTrigger == RewardTrigger.manual)
          'approvedAt': FieldValue.serverTimestamp(),
        // Alle trigger-spezifischen Felder löschen/setzen
        'requiredLevel': FieldValue.delete(),
        'requiredXP': FieldValue.delete(),
        'requiredStars': FieldValue.delete(),
        'requiredStreak': FieldValue.delete(),
        'requiredQuizCount': FieldValue.delete(),
      };

      // Aktiven Trigger-Wert setzen
      if (_triggerValue != null) {
        switch (_selectedTrigger) {
          case RewardTrigger.level:
            updateData['requiredLevel'] = _triggerValue;
            break;
          case RewardTrigger.xp:
            updateData['requiredXP'] = _triggerValue;
            break;
          case RewardTrigger.stars:
            updateData['requiredStars'] = _triggerValue;
            break;
          case RewardTrigger.streak:
            updateData['requiredStreak'] = _triggerValue;
            break;
          case RewardTrigger.quizCount:
            updateData['requiredQuizCount'] = _triggerValue;
            break;
          default:
            break;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('children')
          .doc(widget.child.id)
          .collection('rewards')
          .doc(widget.reward.id)
          .update(updateData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Belohnung aktualisiert'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
}
