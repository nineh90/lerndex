import 'package:flutter/material.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/dashboard_mode.dart';

// ============================================================================
// DASHBOARD MODE BADGE
// Kleines Badge für das Eltern-Dashboard, das zeigt welches
// Dashboard-Layout das Kind bekommt.
// ============================================================================

class DashboardModeBadge extends StatelessWidget {
  final int grade;

  const DashboardModeBadge({super.key, required this.grade});

  @override
  Widget build(BuildContext context) {
    final mode = getDashboardMode(grade);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color(mode).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color(mode).withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_emoji(mode), style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            _label(mode),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _color(mode),
            ),
          ),
        ],
      ),
    );
  }

  String _emoji(DashboardMode mode) {
    switch (mode) {
      case DashboardMode.earlyLearner:
        return '🌟';
      case DashboardMode.primaryLearner:
        return '🎒';
      case DashboardMode.secondaryLearner:
        return '🎓';
    }
  }

  String _label(DashboardMode mode) {
    switch (mode) {
      case DashboardMode.earlyLearner:
        return 'Entdecker';
      case DashboardMode.primaryLearner:
        return 'Lern-Abenteuer';
      case DashboardMode.secondaryLearner:
        return 'Mein Bereich';
    }
  }

  Color _color(DashboardMode mode) {
    switch (mode) {
      case DashboardMode.earlyLearner:
        return Colors.orange;
      case DashboardMode.primaryLearner:
        return Colors.deepPurple;
      case DashboardMode.secondaryLearner:
        return Colors.blue.shade700;
    }
  }
}
