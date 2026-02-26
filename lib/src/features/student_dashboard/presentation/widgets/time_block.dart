import 'package:flutter/material.dart';

class TimeBlock extends StatelessWidget {
  final int value;
  final String label;
  final bool small;

  const TimeBlock({
    super.key,
    required this.value,
    required this.label,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: small ? 8 : 12,
            vertical: small ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: small ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple.shade700,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
      ],
    );
  }
}
