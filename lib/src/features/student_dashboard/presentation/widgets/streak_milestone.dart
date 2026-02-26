/// Daten-Klasse für einen Streak-Meilenstein
class StreakMilestone {
  final int days;
  final String emoji;
  final int xp;
  final String? avatarId;
  final String label;

  const StreakMilestone({
    required this.days,
    required this.emoji,
    required this.xp,
    required this.avatarId,
    required this.label,
  });
}
