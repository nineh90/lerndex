import 'package:flutter/material.dart';

/// Vielseitiges Info-Zeilen-Widget mit zwei Modi:
///
/// Modus 1 — nur [text] (für Info-Cards wie den Task-Generator):
///   InfoRow(icon: Icons.camera_alt, text: 'Fotografiere eine Schulaufgabe')
///
/// Modus 2 — [label] + [value] (für Detailansichten wie BatchDetailScreen):
///   InfoRow(icon: Icons.person, label: 'Schüler', value: 'Max Mustermann')
class InfoRow extends StatelessWidget {
  final IconData icon;

  /// Für Modus 1: einfacher Infotext
  final String? text;

  /// Für Modus 2: Label links, Value rechts
  final String? label;
  final String? value;

  const InfoRow({
    super.key,
    required this.icon,
    this.text,
    this.label,
    this.value,
  }) : assert(
         text != null || (label != null && value != null),
         'Entweder text ODER label+value angeben',
       );

  @override
  Widget build(BuildContext context) {
    // Modus 2: label + value
    if (label != null && value != null) {
      return Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value!,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      );
    }

    // Modus 1: nur text
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.deepPurple.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text!,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
