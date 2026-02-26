import 'package:flutter/material.dart';

// ============================================================================
// ANSWER BUTTON
// ============================================================================

/// Ein Button für Quiz-Antworten
class AnswerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color color;

  const AnswerButton({
    super.key,
    required this.text,
    this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          padding: const EdgeInsets.all(20),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: onPressed == null
                  ? Colors.grey.shade300
                  : color.withOpacity(0.3),
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
