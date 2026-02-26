import 'package:flutter/material.dart';

// =============================================================================
// CLAIMED REWARDS BANNER
// =============================================================================

/// Dezenter Banner für das Eltern-Dashboard.
/// Seriöses Design passend zum Rest des Dashboards — kein kindliches Styling.
class ClaimedRewardsBanner extends StatelessWidget {
  final int count;
  const ClaimedRewardsBanner({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? 'Belohnung eingelöst — bitte aushändigen'
        : '$count Belohnungen eingelöst — bitte aushändigen';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(bottom: BorderSide(color: Colors.deepPurple.shade100)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.redeem_outlined,
            size: 16,
            color: Colors.deepPurple.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.deepPurple.shade700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade600,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
