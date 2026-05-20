import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../rewards/data/xp_service.dart';
import 'tutor_history_screen.dart';
import 'widgets/widgets_info_tile.dart';
import 'widgets/widgets_stat_card.dart';

// ─── Lerndex Brand-Theme für Eltern-Screens ──────────────────────────────────
// Brand-Lila aus main.dart (ColorScheme.fromSeed seed). Wird hier konsistent
// statt der lockeren `Colors.deepPurple`-Variante verwendet.
//
// Komplette Lila-Palette für Variation innerhalb des Brands:
//   _kBrand        — Haupt-Lila (AppBar, Buttons, Streak)
//   _kBrandLight   — Helleres Lila (Akzent, zweite Spalte in Tile-Pairs)
//   _kBrandDeep    — Dunkles Lila (Headers, kritische Werte)
//   _kBrandSoft    — Pastell-Lila (Lernzeit-Block, dezent)
//   _kBrandAccent  — Pink-Lila (Sterne/Belohnungen statt gelb-amber)
//   _kBrandTint    — 10% Lila-Hintergrund für getintete Container
const Color _kBrand = Color(0xFF6B21A8);
const Color _kBrandLight = Color(0xFF9333EA);
const Color _kBrandDeep = Color(0xFF4C1D95);
const Color _kBrandSoft = Color(0xFFA855F7);
const Color _kBrandAccent = Color(0xFFC026D3);
final Color _kBrandTint = const Color(0xFF6B21A8).withOpacity(0.10);

/// Detail-Statistiken für ein Kind
class ChildStatisticsScreen extends ConsumerWidget {
  final ChildModel child;

  const ChildStatisticsScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FB), // sanftes Lila-Beige
      appBar: AppBar(
        title: Text('${child.name} - Statistiken'),
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + bottomInset),
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

              // Fächer-Übersicht (welches Fach wie oft trainiert)
              _buildSubjectsBreakdownSection(),
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
                Icon(Icons.chat, color: _kBrand, size: 24),
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
                  backgroundColor: _kBrand,
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
                color: _kBrand,
                subtitle: 'Erreicht',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.auto_graph,
                label: 'Gesamt XP',
                value: '${child.xp}',
                color: _kBrandLight,
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
                color: _kBrandAccent,
                subtitle: 'Verdient',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.timer,
                label: 'Lernzeit',
                value: child.formattedLearningTime,
                color: _kBrandSoft,
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
                Icon(Icons.trending_up, color: _kBrand, size: 24),
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
                          _kBrand,
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
                color: _kBrandTint,
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
                          color: _kBrand,
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
    return _LearningTimeStatsCard(child: child);
  }

  Widget _buildSubjectsBreakdownSection() {
    return _SubjectsBreakdownCard(child: child);
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
            const Row(
              children: [
                Icon(Icons.quiz, color: _kBrandLight, size: 24),
                SizedBox(width: 8),
                Text(
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
                    color: _kBrandLight,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoTile(
                    icon: Icons.stars,
                    label: 'Perfekt',
                    value: '$perfectQuizzes',
                    color: _kBrandAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoTile(
                    icon: Icons.percent,
                    label: 'Erfolgsrate',
                    value: '$successRate%',
                    color: _kBrand,
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
                valueColor: const AlwaysStoppedAnimation<Color>(_kBrandAccent),
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
            const Row(
              children: [
                Icon(Icons.timeline, color: _kBrand, size: 24),
                SizedBox(width: 8),
                Text(
                  'Aktivität & Streak',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Kompakte Streak-Anzeige: kleines Flammen-Icon, große Zahl,
            // Label rechts daneben — kein riesiger Hero-Block mehr.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _kBrandTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBrand.withOpacity(0.25), width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: _kBrand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_fire_department,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$streak',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: _kBrand,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            streak == 1 ? 'Tag' : 'Tage',
                            style: const TextStyle(
                              fontSize: 16,
                              color: _kBrand,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        streak > 0
                            ? 'Aktuelle Lern-Streak'
                            : 'Noch keine Streak',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Letzte Aktivitäten
            Row(
              children: [
                Expanded(
                  child: InfoTile(
                    icon: Icons.event,
                    label: 'Letztes Lernen',
                    value: lastLearningText,
                    color: _kBrand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoTile(
                    icon: Icons.quiz,
                    label: 'Letztes Quiz',
                    value: lastQuizText,
                    color: _kBrandLight,
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
            const Row(
              children: [
                Icon(Icons.card_giftcard, color: _kBrandAccent, size: 24),
                SizedBox(width: 8),
                Text(
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
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Fehler beim Laden der Belohnungen',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Client-seitig sortieren und limitieren (kein Firestore-Index nötig)
                final rewards = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTime =
                        (aData['claimedAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0;
                    final bTime =
                        (bData['claimedAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0;
                    return bTime.compareTo(aTime);
                  });
                final limited = rewards.take(5).toList();

                if (limited.isEmpty) {
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
                  children: limited.map((doc) {
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
                      leading: const Icon(Icons.redeem, color: _kBrandAccent),
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

// ============================================================================
// LERNZEIT-CARD MIT KORREKTEM DURCHSCHNITT
// ============================================================================
//
// Bug-Fix: Der vorherige Durchschnitt-pro-Tag teilte `totalLearningSeconds`
// durch `now - lastLearningDate` — was nur den Zeitraum seit dem LETZTEN
// Lerntag misst. Wenn das Kind heute gelernt hat → Divisor = 1 → "Durch-
// schnitt" = Gesamtlernzeit (Tester-Befund).
//
// Korrekte Berechnung: Anzahl Dokumente in `learning_stats` zählen — das
// sind die unique Tage an denen tatsächlich gelernt wurde. So bekommt man
// einen realistischen Durchschnitt der echten Lerntage. Alternative wäre
// (firstLearningDate → now), aber das verfälscht den Wert nach unten wenn
// das Kind Pausen einlegt.

class _LearningTimeStatsCard extends StatelessWidget {
  final ChildModel child;
  const _LearningTimeStatsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final hours = child.totalLearningSeconds ~/ 3600;
    final minutes = (child.totalLearningSeconds % 3600) ~/ 60;

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
                Icon(Icons.schedule, color: _kBrandSoft, size: 24),
                SizedBox(width: 8),
                Text(
                  'Lernzeit',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: _kBrandSoft.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _kBrandSoft.withOpacity(0.30),
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
                              color: _kBrandDeep,
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
                                color: _kBrandDeep,
                              ),
                            ),
                          ),
                        ],
                        Text(
                          '$minutes',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: _kBrandDeep,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            'min',
                            style: TextStyle(fontSize: 20, color: _kBrandDeep),
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

            // Durchschnitt: lädt async aus learning_stats
            _AverageRow(child: child),
          ],
        ),
      ),
    );
  }
}

class _AverageRow extends ConsumerWidget {
  final ChildModel child;
  const _AverageRow({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<int>(
      future: _countLearningDays(user.uid, child.id),
      builder: (context, snapshot) {
        final learningDays = snapshot.data ?? 0;
        final avgSeconds = learningDays > 0
            ? child.totalLearningSeconds ~/ learningDays
            : 0;
        final avgMinutes = avgSeconds ~/ 60;
        final avgLabel = learningDays > 0 ? '${avgMinutes}min' : '-';

        return Row(
          children: [
            Expanded(
              child: InfoTile(
                icon: Icons.today,
                label: 'Ø pro Lerntag',
                value: avgLabel,
                color: _kBrandSoft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InfoTile(
                icon: Icons.calendar_today,
                label: 'Lerntage',
                value: snapshot.connectionState == ConnectionState.waiting
                    ? '…'
                    : '$learningDays',
                color: _kBrandSoft,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Zählt unique Lerntage = Anzahl Dokumente in learning_stats-Subcollection.
  Future<int> _countLearningDays(String userId, String childId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('learning_stats')
          .count()
          .get();
      return snap.count ?? 0;
    } catch (e) {
      return 0;
    }
  }
}

// ============================================================================
// FÄCHER-ÜBERSICHT (Tester-Wunsch #4)
// ============================================================================
//
// Zeigt eine horizontale Balken-Übersicht: welches Fach wurde wie oft (in
// Minuten) trainiert. Datenquelle: `learning_stats/{date}.subjects.{name}`
// — pro Tag und Fach inkrementiert. Wir aggregieren über alle Tage.

class _SubjectsBreakdownCard extends ConsumerWidget {
  final ChildModel child;
  const _SubjectsBreakdownCard({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<Map<String, int>>(
      future: _aggregateSubjectSeconds(user.uid, child.id),
      builder: (context, snapshot) {
        final data = snapshot.data ?? <String, int>{};
        final totalSeconds = data.values.fold<int>(0, (a, b) => a + b);

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pie_chart_outline, color: _kBrand, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Fächer-Übersicht',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Lernzeit pro Fach',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (data.isEmpty || totalSeconds == 0)
                  _buildEmptyState()
                else
                  _buildBars(data, totalSeconds),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Noch keine Lerndaten pro Fach. Wird gefüllt, '
              'sobald ${child.name} ein Quiz absolviert hat.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBars(Map<String, int> data, int totalSeconds) {
    // Nach Sekunden absteigend sortieren
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: entries.map((e) {
        final pct = totalSeconds > 0 ? e.value / totalSeconds : 0.0;
        final minutes = e.value ~/ 60;
        final timeLabel = minutes >= 60
            ? '${minutes ~/ 60}h ${minutes % 60}min'
            : '${minutes}min';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${(pct * 100).round()}%)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(_colorFor(e.key)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Aggregiert pro-Fach-Sekunden über alle learning_stats-Dokumente.
  /// Komplexität: O(n) mit n = Anzahl Lerntage.
  Future<Map<String, int>> _aggregateSubjectSeconds(
    String userId,
    String childId,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('learning_stats')
          .get();

      final agg = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final subjects = data['subjects'];
        if (subjects is Map) {
          for (final entry in subjects.entries) {
            final name = entry.key.toString();
            final sec = (entry.value is num) ? (entry.value as num).toInt() : 0;
            agg[name] = (agg[name] ?? 0) + sec;
          }
        }
      }
      return agg;
    } catch (e) {
      return {};
    }
  }

  /// Konsistente Farbe pro Fach (anstatt Random).
  Color _colorFor(String subject) {
    const map = {
      'Mathe': Color(0xFF7E57C2),
      'Zahlen': Color(0xFF7E57C2),
      'Deutsch': Color(0xFFEC407A),
      'Buchstaben': Color(0xFFEC407A),
      'Englisch': Color(0xFF1E88E5),
      'Sachkunde': Color(0xFF43A047),
      'Biologie': Color(0xFF26A69A),
      'Chemie': Color(0xFFAB47BC),
      'Physik': Color(0xFF5C6BC0),
      'Geschichte': Color(0xFF8D6E63),
      'Farben & Formen': Color(0xFFFF7043),
      'KI-Tutor': Color(0xFF00897B),
    };
    return map[subject] ?? Colors.indigo;
  }
}
