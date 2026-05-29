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

  /// Optionale Theme-Farben – werden für Klasse 5+ gesetzt damit die Karte
  /// zum jeweiligen Dashboard-Theme passt.
  final Color? primaryColor;
  final Color? onSurfaceColor;
  final Color? surfaceColor;

  const RewardCard({
    super.key,
    required this.reward,
    this.onClaim,
    this.primaryColor,
    this.onSurfaceColor,
    this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final isClaimed = reward.status == RewardStatus.claimed;
    // Noch nicht freigeschaltet: Belohnung wird gesperrt mit Bedingung gezeigt.
    final isPending = reward.status == RewardStatus.pending;
    // Gedämpfte Darstellung für nicht-einlösbare Belohnungen.
    final muted = isClaimed || isPending;

    // Theme-Farben mit Fallback auf Standard-Lila
    final accent = primaryColor ?? const Color(0xFF7C4DFF);
    final textColor = onSurfaceColor ?? Colors.black87;
    final cardSurface = surfaceColor ?? const Color(0xFFF3F0FF);
    final borderColor = muted
        ? Colors.grey.shade300
        : primaryColor?.withValues(alpha: 0.6) ?? const Color(0xFF9C64FF);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: muted ? 1 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 2),
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
                          color: muted ? Colors.grey : textColor,
                        ),
                      ),
                      if (reward.description.isNotEmpty)
                        Text(
                          reward.description,
                          style: TextStyle(
                            fontSize: 14,
                            color: muted
                                ? Colors.grey.shade500
                                : textColor.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isClaimed)
                  const Icon(Icons.check_circle, color: Colors.green, size: 32)
                else if (isPending)
                  Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 28),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: muted ? Colors.grey.shade100 : cardSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.card_giftcard,
                    color: muted ? Colors.grey : accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reward.reward,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: muted ? Colors.grey : textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Freischalten: ${reward.conditionText}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (onClaim != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onClaim,
                  icon: const Icon(Icons.redeem),
                  label: const Text('Belohnung einlösen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
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
