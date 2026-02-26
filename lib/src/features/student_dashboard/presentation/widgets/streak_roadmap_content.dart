import 'package:flutter/material.dart';
import 'streak_milestone.dart';

// ============================================================================
// STREAK ROADMAP CONTENT – Inhalt der ausklappbaren Streak-Belohnungen
// (wird innerhalb der LiveLearningTimeCard eingebettet)
// ============================================================================

class StreakRoadmapContent extends StatelessWidget {
  final int streak;

  const StreakRoadmapContent({super.key, required this.streak});

  // Definition der Streak-Meilensteine (gespiegelt aus system_rewards_initializer)
  static const List<StreakMilestone> _milestones = [
    StreakMilestone(
      days: 7,
      emoji: '🔥',
      xp: 50,
      avatarId: null,
      label: '+50 XP',
    ),
    StreakMilestone(
      days: 14,
      emoji: '⚡',
      xp: 100,
      avatarId: 'avatar-streak-uncommon',
      label: '+100 XP + Avatar 🎭',
    ),
    StreakMilestone(
      days: 21,
      emoji: '🌟',
      xp: 200,
      avatarId: null,
      label: '+200 XP',
    ),
    StreakMilestone(
      days: 28,
      emoji: '👑',
      xp: 300,
      avatarId: 'avatar-streak-epic',
      label: '+300 XP + Avatar 🎭',
    ),
    StreakMilestone(
      days: 35,
      emoji: '💎',
      xp: 500,
      avatarId: null,
      label: '+500 XP',
    ),
    StreakMilestone(
      days: 42,
      emoji: '🏆',
      xp: 750,
      avatarId: 'avatar-streak-legendary',
      label: '+750 XP + Avatar 🎭',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final nextMilestone = _milestones.firstWhere(
      (m) => m.days > streak,
      orElse: () => _milestones.last,
    );
    final daysLeft = (nextMilestone.days - streak).clamp(0, 999);
    final alreadyAtMax = streak >= _milestones.last.days;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trennlinie
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 12),

        // Header
        Row(
          children: [
            Text(
              'Streak-Belohnungen',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
            ),
            const Spacer(),
            if (!alreadyAtMax)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Noch $daysLeft ${daysLeft == 1 ? 'Tag' : 'Tage'}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Meilenstein-Liste
        ...(_milestones.map((m) {
          final isDone = streak >= m.days;
          final isNext = !alreadyAtMax && m.days == nextMilestone.days;
          final hasAvatar = m.avatarId != null;

          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                // Icon-Kreis
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? Colors.orange.shade400
                        : isNext
                        ? Colors.orange.shade50
                        : Colors.grey.shade100,
                    border: Border.all(
                      color: isDone
                          ? Colors.orange.shade600
                          : isNext
                          ? Colors.orange.shade300
                          : Colors.grey.shade300,
                      width: isNext ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 17,
                          )
                        : Text(m.emoji, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 10),

                // Label
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '${m.days} Tage',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isNext
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isDone
                              ? Colors.grey[400]
                              : isNext
                              ? Colors.orange.shade800
                              : Colors.grey.shade600,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (hasAvatar && !isDone) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: const Text(
                            '🎭',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // XP Badge
                if (!isDone)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isNext
                          ? Colors.orange.shade400
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isNext ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList()),

        if (alreadyAtMax)
          Center(
            child: Text(
              '🏆 Alle Streak-Belohnungen erreicht!',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade700,
              ),
            ),
          ),
      ],
    );
  }
}
