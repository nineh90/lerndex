import 'package:flutter/material.dart';

/// Vereinheitlichte Statistik-Kachel – funktioniert in beiden Dashboards.
///
/// **Student-Modus** (kein [subtitle]):
///   Kompakter Container mit Icon, Wert und Label.
///   [labelColor] überschreibt das Standard-Grau (für dunkle Themes).
///
/// **Parent-Modus** (mit [subtitle]):
///   Card mit Gradient, breitem Layout und Untertitel.
class StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? subtitle; // Parent-Modus: Untertitel unter dem Label
  final Color? labelColor; // Student-Modus: Textfarbe für Label (dunkle Themes)

  const StatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.subtitle,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    // Parent-Modus: subtitle angegeben → Card mit Gradient
    if (subtitle != null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    // Student-Modus: kompakter Container
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: labelColor ?? Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
