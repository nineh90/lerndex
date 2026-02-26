import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../rewards/data/xp_service.dart';
import 'tutor_history_screen.dart';
import 'widgets/info_tile.dart';
import 'widgets/stat_card.dart';

/// Detail-Statistiken für ein Kind
class ChildStatisticsScreen extends ConsumerWidget {
  final ChildModel child;

  const ChildStatisticsScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${child.name} - Statistiken'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Übersicht-Kacheln
            _buildOverviewSection(),
            const SizedBox(height: 24),

            // XP & Level Fortschritt
            _buildLevelProgressSection(),
            const SizedBox(height: 24),

            // Lernzeit
            _buildLearningTimeSection(),
            const SizedBox(height: 24),

            // Quiz-Statistiken
            _buildQuizStatsSection(),
            const SizedBox(height: 24),

            // Streak & Aktivität
            _buildActivitySection(),
            const SizedBox(height: 24),

            // Belohnungen
            _buildRewardsSection(ref),
            const SizedBox(height: 24),

            // Tutor-Gespräche
            _buildTutorSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorSection(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.chat, color: Colors.deepPurple, size: 24),
                SizedBox(width: 8),
                Text(
                  'Tutor-Gespräche',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Sehen Sie alle Gespräche zwischen ${child.name} und dem KI-Tutor.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TutorHistoryScreen(child: child),
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('Alle Gespräche anzeigen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Übersicht',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.emoji_events,
                label: 'Level',
                value: '${child.level}',
                color: Colors.orange,
                subtitle: 'Erreicht',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.auto_graph,
                label: 'Gesamt XP',
                value: '${child.xp}',
                color: Colors.blue,
                subtitle: 'Gesammelt',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.stars,
                label: 'Sterne',
                value: '${child.stars}',
                color: Colors.amber,
                subtitle: 'Verdient',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.timer,
                label: 'Lernzeit',
                value: child.formattedLearningTime,
                color: Colors.green,
                subtitle: 'Gesamt',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLevelProgressSection() {
    final xpForNextLevel = XPService.calculateXPForLevel(child.level);
    int currentLevelXP = child.xp;

    // Subtrahiere XP aller vorherigen Levels
    for (int i = 1; i < child.level; i++) {
      currentLevelXP -= XPService.calculateXPForLevel(i);
    }

    final progress = currentLevelXP / xpForNextLevel;
    final percentage = (progress * 100).toInt();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.trending_up, color: Colors.deepPurple, size: 24),
                SizedBox(width: 8),
                Text(
                  'Level-Fortschritt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Großer Kreis-Progress
            Center(
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Progress Circle
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.deepPurple,
                        ),
                      ),
                    ),
                    // Level in der Mitte
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Level ${child.level}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$percentage%',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Aktuelles Level:'),
                      Text(
                        'Level ${child.level}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Aktueller XP:'),
                      Text(
                        '$currentLevelXP XP',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bis zum nächsten Level:'),
                      Text(
                        '${xpForNextLevel - currentLevelXP} XP',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningTimeSection() {
    final hours = child.totalLearningSeconds ~/ 3600;
    final minutes = (child.totalLearningSeconds % 3600) ~/ 60;
    final seconds = child.totalLearningSeconds % 60;

    // Berechne Durchschnitt pro Tag (wenn lastLearningDate vorhanden)
    String avgPerDay = '-';
    if (child.lastLearningDate != null) {
      final daysSinceStart =
          DateTime.now().difference(child.lastLearningDate!).inDays + 1;
      if (daysSinceStart > 0) {
        final avgSeconds = child.totalLearningSeconds ~/ daysSinceStart;
        final avgMinutes = avgSeconds ~/ 60;
        avgPerDay = '${avgMinutes}min';
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.schedule, color: Colors.green, size: 24),
                SizedBox(width: 8),
                Text(
                  'Lernzeit',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Große Anzeige
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hours > 0) ...[
                          Text(
                            '$hours',
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(
                              bottom: 8,
                              left: 4,
                              right: 12,
                            ),
                            child: Text(
                              'h',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ],
                        Text(
                          '$minutes',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            'min',
                            style: TextStyle(fontSize: 20, color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gesamte Lernzeit',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Details
            Row(
              children: [
                Expanded(
                  child: InfoTile(
                    icon: Icons.today,
                    label: 'Ø pro Tag',
                    value: avgPerDay,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoTile(
                    icon: Icons.timer_outlined,
                    label: 'Gesamt',
                    value: '${child.totalLearningSeconds}s',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizStatsSection() {
    final totalQuizzes = child.totalQuizzes ?? 0;
    final perfectQuizzes = child.perfectQuizzes ?? 0;
    final successRate = totalQuizzes > 0
        ? ((perfectQuizzes / totalQuizzes) * 100).toInt()
        : 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.quiz, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Quiz-Statistiken',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: InfoTile(
                    icon: Icons.assignment_turned_in,
                    label: 'Absolviert',
                    value: '$totalQuizzes',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoTile(
                    icon: Icons.stars,
                    label: 'Perfekt',
                    value: '$perfectQuizzes',
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoTile(
                    icon: Icons.percent,
                    label: 'Erfolgsrate',
                    value: '$successRate%',
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            if (totalQuizzes > 0) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: perfectQuizzes / totalQuizzes,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
              const SizedBox(height: 8),
              Text(
                '$perfectQuizzes von $totalQuizzes perfekt gelöst',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySection() {
    final streak = child.streak ?? 0;
    final lastLearning = child.lastLearningDate;
    final lastQuiz = child.lastQuizDate;

    String lastLearningText = 'Noch keine Aktivität';
    if (lastLearning != null) {
      final diff = DateTime.now().difference(lastLearning);
      if (diff.inDays == 0) {
        lastLearningText = 'Heute';
      } else if (diff.inDays == 1) {
        lastLearningText = 'Gestern';
      } else {
        lastLearningText = 'Vor ${diff.inDays} Tagen';
      }
    }

    String lastQuizText = 'Noch kein Quiz';
    if (lastQuiz != null) {
      final diff = DateTime.now().difference(lastQuiz);
      if (diff.inDays == 0) {
        lastQuizText = 'Heute';
      } else if (diff.inDays == 1) {
        lastQuizText = 'Gestern';
      } else {
        lastQuizText = 'Vor ${diff.inDays} Tagen';
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_fire_department,
                  color: Colors.orange,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Aktivität & Streak',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Streak-Anzeige
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.shade300,
                      Colors.deepOrange.shade400,
                    ],
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
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Tage Streak',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Letzte Aktivitäten
            Row(
              children: [
                Expanded(
                  child: InfoTile(
                    icon: Icons.event,
                    label: 'Letztes Lernen',
                    value: lastLearningText,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoTile(
                    icon: Icons.quiz,
                    label: 'Letztes Quiz',
                    value: lastQuizText,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardsSection(WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.card_giftcard, color: Colors.amber, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Belohnungen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('children')
                  .doc(child.id)
                  .collection('rewards')
                  .where('status', isEqualTo: 'claimed')
                  .orderBy('claimedAt', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rewards = snapshot.data!.docs;

                if (rewards.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Noch keine Belohnungen eingelöst',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  );
                }

                return Column(
                  children: rewards.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final claimedAt = (data['claimedAt'] as Timestamp?)
                        ?.toDate();

                    String timeAgo = '';
                    if (claimedAt != null) {
                      final diff = DateTime.now().difference(claimedAt);
                      if (diff.inDays == 0) {
                        timeAgo = 'Heute';
                      } else if (diff.inDays == 1) {
                        timeAgo = 'Gestern';
                      } else {
                        timeAgo = 'Vor ${diff.inDays} Tagen';
                      }
                    }

                    return ListTile(
                      leading: const Icon(Icons.redeem, color: Colors.amber),
                      title: Text(data['title'] ?? 'Belohnung'),
                      subtitle: Text(data['reward'] ?? ''),
                      trailing: Text(
                        timeAgo,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
