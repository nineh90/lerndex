import 'package:flutter/material.dart';

// ============================================================================
// REWARD ROW
// ============================================================================

/// Eine Zeile zur Anzeige von Belohnungen (Sterne/XP) im Erfolgs-Screen
class RewardRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const RewardRow({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
