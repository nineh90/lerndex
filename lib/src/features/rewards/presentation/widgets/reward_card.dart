import 'package:flutter/material.dart';
import '../../domain/reward_model.dart';
import '../../domain/reward_enums.dart';

// ============================================================================
// REWARD CARD
// ============================================================================

/// Eine Karte zur Anzeige einer Belohnung für das Kind
class RewardCard extends StatelessWidget {
  final RewardModel reward;
  final VoidCallback? onClaim;

  const RewardCard({super.key, required this.reward, this.onClaim});

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
