import 'package:flutter/material.dart';

class TimeSep extends StatelessWidget {
  const TimeSep({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 3, right: 3),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple.shade300,
        ),
      ),
    );
  }
}
