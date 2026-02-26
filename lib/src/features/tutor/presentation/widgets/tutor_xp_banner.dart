import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tutor_provider.dart';

const int _kMaxXpPerSession = 20;

// ============================================================================
// REAKTIVER XP-BANNER
// ============================================================================

class TutorXpBanner extends ConsumerWidget {
  final String childId;
  const TutorXpBanner({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionXP = ref.watch(tutorSessionXpProvider(childId));
    final remaining = (_kMaxXpPerSession - sessionXP).clamp(
      0,
      _kMaxXpPerSession,
    );
    final limitReached = remaining <= 0;
    final progress = (sessionXP / _kMaxXpPerSession).clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: limitReached ? Colors.orange.shade50 : Colors.purple.shade50,
      child: Row(
        children: [
          const Text('⚡', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      limitReached
                          ? 'Session-Limit erreicht 🎉'
                          : 'Hol dir noch $remaining XP – lern mit mir!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: limitReached
                            ? Colors.orange.shade800
                            : Colors.purple.shade800,
                      ),
                    ),
                    Text(
                      '$sessionXP / $_kMaxXpPerSession XP',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: progress),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: Colors.purple.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        limitReached ? Colors.orange : Colors.deepPurple,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
