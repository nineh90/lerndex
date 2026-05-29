import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/data/auth_repository.dart';
import 'streak_roadmap_content.dart';
import 'time_block.dart';
import 'time_sep.dart';

// ============================================================================
// LIVE LERNZEIT CARD (Home Tab) – kompaktes Layout mit Streak + Info-Icon
// ============================================================================

class LiveLearningTimeCard extends ConsumerStatefulWidget {
  final String childId;

  const LiveLearningTimeCard({super.key, required this.childId});

  @override
  ConsumerState<LiveLearningTimeCard> createState() =>
      _LiveLearningTimeCardState();
}

class _LiveLearningTimeCardState extends ConsumerState<LiveLearningTimeCard> {
  bool _showRoadmap = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(widget.childId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final totalSeconds = data?['totalLearningSeconds'] as int? ?? 0;

        final hours = totalSeconds ~/ 3600;
        final minutes = (totalSeconds % 3600) ~/ 60;
        final secs = totalSeconds % 60;

        final streak = data?['streak'] as int? ?? 0;
        final isActive = data?['isCurrentlyLearning'] as bool? ?? false;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Hauptzeile: Lernzeit + Streak ────────────────────────────
              Row(
                children: [
                  // Lernzeit
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Colors.deepPurple.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Lernzeit gesamt',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Live',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (hours > 0) ...[
                              TimeBlock(value: hours, label: 'Std'),
                              const TimeSep(),
                            ],
                            TimeBlock(value: minutes, label: 'Min'),
                            const TimeSep(),
                            TimeBlock(value: secs, label: 'Sek', small: true),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Trennlinie
                  Container(
                    width: 1,
                    height: 52,
                    color: Colors.grey.shade200,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),

                  // Streak + Info-Icon
                  Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            size: 14,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Streak',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // ── Info-Icon ──────────────────────────────────
                          GestureDetector(
                            onTap: () =>
                                setState(() => _showRoadmap = !_showRoadmap),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: _showRoadmap
                                    ? Colors.orange.shade100
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _showRoadmap
                                    ? Icons.info_rounded
                                    : Icons.info_outline_rounded,
                                size: 15,
                                color: _showRoadmap
                                    ? Colors.orange.shade600
                                    : Colors.grey[400],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$streak',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: streak > 0 ? Colors.orange : Colors.grey,
                        ),
                      ),
                      Text(
                        streak == 1 ? 'Tag' : 'Tage',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),

              // ── Ausklappbare Streak-Roadmap ───────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: _showRoadmap
                    ? Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: StreakRoadmapContent(streak: streak),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}
