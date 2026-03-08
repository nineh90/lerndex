import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/child_model.dart';
import 'stat_card.dart';
import 'section_header.dart';
import 'info_tile.dart';

// ============================================================================
// TAB 3: STATISTIK – eigene Seite, vollständig erhalten
// ============================================================================

class StatisticsTab extends ConsumerWidget {
  final ChildModel child;

  const StatisticsTab({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();

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
        final stars = data?['stars'] as int? ?? child.stars;
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
              const SectionHeader(
                icon: Icons.emoji_events,
                title: 'Meine Erfolge',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.star,
                      color: Colors.amber,
                      value: '$stars',
                      label: 'Sterne',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.emoji_events,
                      color: Colors.deepPurple,
                      value: 'Lvl $level',
                      label: 'Level',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.bolt,
                      color: Colors.orange,
                      value: '$xp XP',
                      label: 'Gesamt',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const SectionHeader(
                icon: Icons.local_fire_department,
                title: 'Lern-Streak',
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: streak > 0
                        ? [Colors.orange.shade400, Colors.deepOrange.shade600]
                        : [Colors.grey.shade300, Colors.grey.shade400],
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
              const SectionHeader(icon: Icons.quiz, title: 'Quiz-Statistiken'),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
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
                        ),
                      ),
                      Expanded(
                        child: InfoTile(
                          icon: Icons.workspace_premium,
                          label: 'Perfekt',
                          value: '$perfectQuizzes',
                        ),
                      ),
                      Expanded(
                        child: InfoTile(
                          icon: Icons.percent,
                          label: 'Erfolgsrate',
                          value: '$successRate%',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(icon: Icons.timer, title: 'Lernzeit'),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.deepPurple,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Gesamte Lernzeit',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
