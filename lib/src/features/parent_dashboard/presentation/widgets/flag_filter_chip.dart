import 'package:flutter/material.dart';

// ============================================================================
// FLAG-FILTER CHIP
// ============================================================================

class FlagFilterChip extends StatelessWidget {
  final String label;
  final String flagValue;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const FlagFilterChip({
    super.key,
    required this.label,
    required this.flagValue,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(isSelected ? 1.0 : 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
