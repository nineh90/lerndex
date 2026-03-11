import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? textColor; // optional: überschreibt Standard-Dunkelfarbe

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? const Color(0xFF1A1A2E);
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
