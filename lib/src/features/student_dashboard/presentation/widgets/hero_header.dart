import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/child_model.dart';
import '../../../rewards/data/xp_service.dart';
import 'header_badge.dart';

// ============================================================================
// HERO HEADER – nahtlos an AppBar, enthält Level/Sterne/XP
// Live via Firestore-Stream → updated sofort nach Tutor-Session
// ============================================================================

class HeroHeader extends ConsumerWidget {
  final ChildModel child;

  const HeroHeader({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple, Color(0xFF7B1FA2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: user == null
          ? _buildContent(
              child.level,
              child.stars,
              child.xp,
              child.xpToNextLevel,
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('children')
                  .doc(child.id)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final level = data?['level'] as int? ?? child.level;
                final stars = data?['stars'] as int? ?? child.stars;
                final xp = data?['xp'] as int? ?? child.xp;
                final xpToNextLevel =
                    data?['xpToNextLevel'] as int? ?? child.xpToNextLevel;
                return _buildContent(level, stars, xp, xpToNextLevel);
              },
            ),
    );
  }

  Widget _buildContent(int level, int stars, int xp, int xpToNextLevel) {
    // Korrekte XP-Berechnung: Nur XP im aktuellen Level (nicht kumulativ)
    final xpForThisLevel = XPService.calculateXPForLevel(level);
    final xpInLevel = XPService.calculateXPInCurrentLevel(xp, level);
    final isMaxLevel = level >= XPService.maxLevel;
    final progress = isMaxLevel
        ? 1.0
        : (xpInLevel / xpForThisLevel).clamp(0.0, 1.0);
    final rank = XPService.getRankForLevel(level);
    final xpRemaining = isMaxLevel ? 0 : (xpForThisLevel - xpInLevel);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            HeaderBadge(emoji: '🏆', label: 'Level $level'),
            HeaderBadge(emoji: rank.emoji, label: rank.title),
            HeaderBadge(emoji: '⭐', label: '$stars Sterne'),
          ],
        ),
        const SizedBox(height: 18),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$xpInLevel / $xpForThisLevel XP',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  isMaxLevel
                      ? '🏆 Max Level!'
                      : 'Noch $xpRemaining bis Lvl ${level + 1}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: progress),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                builder: (_, value, __) => LinearProgressIndicator(
                  value: value,
                  minHeight: 14,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
