import 'package:flutter/material.dart';
import '../../../auth/domain/child_model.dart';
import '../../domain/reward_model.dart';
import '../../domain/reward_enums.dart';

// ============================================================================
// REWARD CARD
// ============================================================================

class RewardManageCard extends StatelessWidget {
  final RewardModel reward;
  final ChildModel child;
  final String userId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleApproval;
  final VoidCallback onMarkSeen;

  const RewardManageCard({
    super.key,
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
              : const Color(0xFF9C64FF),
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
                  : const Color(0xFFF3F0FF),
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
                                color: const Color(0xFF7C4DFF),
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
                    color: const Color(0xFFF3F0FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCDB8FF)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.card_giftcard,
                        color: const Color(0xFF7C4DFF),
                      ),
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
                            : const Color(0xFF9C64FF),
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
