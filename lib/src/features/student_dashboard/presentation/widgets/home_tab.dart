import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/domain/child_model.dart';
import '../subject_config.dart';
import 'hero_header.dart';
// import 'live_learning_time_card.dart'; // TODO
// import 'playful_subject_tile.dart'; // TODO

// ============================================================================
// TAB 0: HOME – NEU GESTALTET (ohne Statistiken)
// ============================================================================

class HomeTab extends ConsumerWidget {
  final ChildModel child;

  const HomeTab({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = getSubjectsForChild(child);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero-Header (nahtlos an AppBar) ─────────────────────────────
          HeroHeader(child: child),

          // ── Live Lernzeit + Streak ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            // child: LiveLearningTimeCard(childId: child.id),
          ),

          // ── Fächer-Titel ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _subjectsHeadline(child),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),

          // ── Dynamisches Fächer-Grid ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.35,
              ),
              itemCount: subjects.length,
              itemBuilder: (context, index) {
                // final s = subjects[index];
                return const SizedBox();
                /* return PlayfulSubjectTile(
                  config: s,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuizScreen(subject: s.subject),
                    ),
                  ),
                ); */
              },
            ),
          ),

          const SizedBox(height: 100), // Platz für FAB + BottomBar
        ],
      ),
    );
  }

  String _subjectsHeadline(ChildModel child) {
    if (child.grade <= 4) return 'Was lernst du heute? 🎯';
    if (child.grade <= 10) return 'Deine Fächer';
    return 'Fächer & Themen';
  }
}
