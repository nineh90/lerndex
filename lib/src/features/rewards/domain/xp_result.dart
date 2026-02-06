/// Ergebnis einer XP-Vergabe
class XPResult {
  final int newXP;
  final int newLevel;
  final bool leveledUp;
  final int xpGained;
  final int xpToNextLevel;

  XPResult({
    required this.newXP,
    required this.newLevel,
    required this.leveledUp,
    required this.xpGained,
    required this.xpToNextLevel,
  });

  @override
  String toString() {
    return 'XPResult(newXP: $newXP, newLevel: $newLevel, leveledUp: $leveledUp, xpGained: $xpGained)';
  }
}