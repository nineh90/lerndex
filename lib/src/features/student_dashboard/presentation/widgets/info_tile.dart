import 'package:flutter/material.dart';

/// Vereinheitlichte Info-Kachel – funktioniert in beiden Dashboards.
///
/// **Parent-Modus** ([color] angegeben):
///   Farbiger Container mit Hintergrund-Tint, Icon in der übergebenen Farbe.
///
/// **Student-Modus** ([textColor] angegeben, kein [color]):
///   Flaches Layout ohne Container, Farben aus dem Dashboard-Theme.
///   [textColor] steuert Icon, Wert und Label für dunkle Themes.
class InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color; // Parent-Modus: Akzentfarbe + Container-Tint
  final Color? textColor; // Student-Modus: Theme-Textfarbe (dunkle Themes)

  const InfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    // Parent-Modus: color übergeben → Container mit Hintergrund-Tint
    if (color != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color!.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Student-Modus: flaches Layout, Farbe aus textColor oder Fallback
    final effectiveColor = textColor ?? Colors.deepPurple;
    final labelColor = textColor?.withValues(alpha: 0.6) ?? Colors.grey[600]!;
    return Column(
      children: [
        Icon(icon, color: effectiveColor, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: effectiveColor,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: labelColor)),
      ],
    );
  }
}
