import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/child_model.dart';
import 'stat_card.dart';
import 'section_header.dart';
import 'info_tile.dart';
import 'dashboard_theme_provider.dart';

// ============================================================================
// TAB 3: STATISTIK – eigene Seite, vollständig erhalten
// ============================================================================

class StatisticsTab extends ConsumerWidget {
  final ChildModel child;

  /// Wenn false (Klasse 3–4): feste dunkle Farben auf weißem Hintergrund.
  /// Wenn true (Klasse 5+):   Farben aus dem gewählten Dashboard-Theme.
  final bool useTheme;

  const StatisticsTab({super.key, required this.child, this.useTheme = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();

    // Feste Farben für Klasse 3–4 (weißer Hintergrund, kein Theme)
    late final Color textColor;
    late final Color subtleColor;
    late final Color? cardColor;
    late final Color accentColor;

    if (!useTheme) {
      textColor = const Color(0xFF1A1A2E);
      subtleColor = Colors.grey[600]!;
      cardColor = null;
      accentColor = Colors.deepPurple;
    } else {
      // Theme laden – Slate (isDark=false) behält dunkle Farben, alle anderen
      // dunklen Themes bekommen helle Textfarben.
      final themeState = ref.watch(
        dashboardThemeProvider((userId: user.uid, childId: child.id)),
      );
      final theme = themeState.theme;
      textColor = theme.onSurface;
      subtleColor = theme.isDark
          ? theme.onSurface.withValues(alpha: 0.55)
          : Colors.grey[600]!;
      cardColor = theme.isDark ? theme.surface : null;
      accentColor = theme.primary;
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(child.id)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;

        final totalSeconds = data?['totalLearningSeconds'] as int? ?? 0;
        final streak = data?['streak'] as int? ?? 0;
        final totalQuizzes = data?['totalQuizzes'] as int? ?? 0;
        final perfectQuizzes = data?['perfectQuizzes'] as int? ?? 0;
        final xp = data?['xp'] as int? ?? child.xp;
        final level = data?['level'] as int? ?? child.level;
        final successRate = totalQuizzes > 0
            ? (perfectQuizzes / totalQuizzes * 100).round()
            : 0;

        final hours = totalSeconds ~/ 3600;
        final minutes = (totalSeconds % 3600) ~/ 60;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                icon: Icons.emoji_events,
                title: 'Meine Erfolge',
                textColor: textColor,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.emoji_events,
                      color: Colors.deepPurple,
                      value: 'Lvl $level',
                      label: 'Level',
                      labelColor: subtleColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.bolt,
                      color: Colors.orange,
                      value: '$xp XP',
                      label: 'Gesamt',
                      labelColor: subtleColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionHeader(
                icon: Icons.local_fire_department,
                title: 'Lern-Streak',
                textColor: textColor,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: streak > 0
                        ? [Colors.orange.shade400, Colors.deepOrange.shade600]
                        : [Colors.grey.shade500, Colors.grey.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      size: 48,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$streak',
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Tage Lern-Streak',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    if (streak == 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Lerne heute, um deinen Streak zu starten!',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                icon: Icons.quiz,
                title: 'Quiz-Statistiken',
                textColor: textColor,
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: InfoTile(
                          icon: Icons.assignment_turned_in,
                          label: 'Absolviert',
                          value: '$totalQuizzes',
                          textColor: textColor,
                        ),
                      ),
                      Expanded(
                        child: InfoTile(
                          icon: Icons.workspace_premium,
                          label: 'Perfekt',
                          value: '$perfectQuizzes',
                          textColor: textColor,
                        ),
                      ),
                      Expanded(
                        child: InfoTile(
                          icon: Icons.percent,
                          label: 'Erfolgsrate',
                          value: '$successRate%',
                          textColor: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(
                icon: Icons.timer,
                title: 'Lernzeit',
                textColor: textColor,
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.access_time, color: accentColor, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Gesamte Lernzeit',
                        style: TextStyle(fontSize: 13, color: subtleColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }
}
