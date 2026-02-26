import 'package:flutter/material.dart';

// ============================================================================
// CONTENT FLAG BANNER
// ============================================================================

class ContentFlagBanner extends StatelessWidget {
  final String flag;

  const ContentFlagBanner({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    final isCritical = flag == 'critical';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isCritical ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCritical ? Colors.red.shade200 : Colors.orange.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.warning_rounded : Icons.info_outline,
            size: 16,
            color: isCritical ? Colors.red.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isCritical
                  ? '🚨 Bedenklicher Inhalt – bitte Gespräch prüfen'
                  : '⚠️ Nicht-Schulthema – außerhalb des Lernbereichs',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isCritical
                    ? Colors.red.shade700
                    : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
