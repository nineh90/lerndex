import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../quiz/presentation/quiz_screen.dart';
import '../../rewards/presentation/rewards_screen.dart';
import '../../tutor/presentation/tutor_screen.dart';
import '../../tutor/presentation/tutor_provider.dart';
import '../../rewards/data/xp_service.dart';

// ============================================================================
// STUDENT DASHBOARD - MIT BOTTOM APP BAR
// ============================================================================

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState
    extends ConsumerState<StudentDashboardScreen> {
  int _currentTab = 0; // 0=Home, 1=Belohnungen, 2=Verlauf, 3=Statistik

  @override
  Widget build(BuildContext context) {
    final activeChild = ref.watch(activeChildProvider);
    if (activeChild == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle(activeChild.name)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ref.read(activeChildProvider.notifier).deselect(),
          tooltip: 'Abmelden',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _showAvatarSettings(context, activeChild),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Text(
                  activeChild.name[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(activeChild),
      // ── FAB: Tutor — rund, passend zur CircularNotchedRectangle ──────
      floatingActionButton: FloatingActionButton(
        heroTag: 'tutor_fab',
        onPressed: () => _openTutor(context, activeChild),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: 'KI-Tutor öffnen',
        child: const Icon(Icons.smart_toy, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      // ── Bottom App Bar ────────────────────────────────────────────────
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        elevation: 8,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Lernen',
                selected: _currentTab == 0,
                onTap: () => setState(() => _currentTab = 0),
              ),
              _NavItem(
                icon: Icons.card_giftcard_outlined,
                activeIcon: Icons.card_giftcard,
                label: 'Belohnungen',
                selected: _currentTab == 1,
                onTap: () => setState(() => _currentTab = 1),
              ),
              // Mitte: FAB-Platzhalter
              const SizedBox(width: 60),
              _NavItem(
                icon: Icons.history_outlined,
                activeIcon: Icons.history,
                label: 'Verlauf',
                selected: _currentTab == 2,
                onTap: () => setState(() => _currentTab = 2),
              ),
              _NavItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart,
                label: 'Statistik',
                selected: _currentTab == 3,
                onTap: () => setState(() => _currentTab = 3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _appBarTitle(String name) {
    switch (_currentTab) {
      case 0:
        return 'Hallo $name! 👋';
      case 1:
        return '🎁 Meine Belohnungen';
      case 2:
        return '💬 Tutor-Verlauf';
      case 3:
        return '📊 Meine Statistiken';
      default:
        return 'Hallo $name!';
    }
  }

  Widget _buildBody(ChildModel activeChild) {
    switch (_currentTab) {
      case 0:
        return _HomeTab(child: activeChild);
      case 1:
        return const RewardsScreen();
      case 2:
        return _TutorHistoryTab(child: activeChild);
      case 3:
        return _StatisticsTab(child: activeChild);
      default:
        return _HomeTab(child: activeChild);
    }
  }

  // Avatar-Einstellungen Dialog
  void _showAvatarSettings(BuildContext context, ChildModel child) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.deepPurple.shade100,
              child: Text(
                child.name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              child.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Level ${child.level} · ${child.stars} ⭐',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepPurple.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.brush_outlined, color: Colors.deepPurple),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Avatar anpassen',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Folgt in Kürze',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Icon(Icons.lock_outline, color: Colors.grey[400], size: 18),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // Tutor öffnen und nach Schließen den Chat automatisch löschen & archivieren
  Future<void> _openTutor(BuildContext context, ChildModel child) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutorScreen()),
    );
    // ✅ Chat nach Schließen automatisch löschen (Session bleibt für Eltern)
    if (mounted) {
      final provider = ref.read(tutorProvider);
      if (provider != null) {
        ref.read(provider.notifier).clearChat();
      }
    }
  }
}

// ============================================================================
// NAV ITEM WIDGET
// ============================================================================

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? activeIcon : icon,
              color: selected ? Colors.deepPurple : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? Colors.deepPurple : Colors.grey,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 0: HOME - LERNEN
// ============================================================================

class _HomeTab extends ConsumerWidget {
  final ChildModel child;

  const _HomeTab({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusHeader(child: child),
          const SizedBox(height: 20),

          // ✅ Live Lernzeit mit Tagen/Stunden/Minuten/Sekunden
          _LiveLearningTimeCard(childId: child.id),
          const SizedBox(height: 24),

          const Text(
            'Wähle ein Fach zum Lernen:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.1,
            children: [
              _SubjectTile(
                title: 'Mathe',
                icon: Icons.calculate,
                color: Colors.orange,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => QuizScreen(subject: 'Mathe'))),
              ),
              _SubjectTile(
                title: 'Deutsch',
                icon: Icons.menu_book,
                color: Colors.redAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => QuizScreen(subject: 'Deutsch'))),
              ),
              _SubjectTile(
                title: 'Englisch',
                icon: Icons.language,
                color: Colors.blue,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => QuizScreen(subject: 'Englisch'))),
              ),
              _SubjectTile(
                title: 'Sachkunde',
                icon: Icons.wb_sunny,
                color: Colors.green,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => QuizScreen(subject: 'Sachkunde'))),
              ),
            ],
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 2: TUTOR-VERLAUF (Schüler-Sicht)
// ============================================================================

class _TutorHistoryTab extends ConsumerWidget {
  final ChildModel child;

  const _TutorHistoryTab({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const Center(child: Text('Nicht angemeldet'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(child.id)
          .collection('tutor_sessions')
          .orderBy('startedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('Noch kein Verlauf',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('Starte ein Gespräch mit dem Tutor!',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400])),
              ],
            ),
          );
        }

        final sessions = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index].data() as Map<String, dynamic>;
            final startedAt = (session['startedAt'] as Timestamp?)?.toDate();
            final topic = session['detectedTopic'] as String? ?? 'Allgemein';
            final msgCount = session['messageCount'] as int? ?? 0;
            final status = session['status'] as String? ?? 'active';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.deepPurple.shade100,
                  child: const Icon(Icons.chat, color: Colors.deepPurple, size: 20),
                ),
                title: Text(topic, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  startedAt != null ? _formatDate(startedAt) : 'Datum unbekannt',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$msgCount Nachrichten', style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: status == 'completed'
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status == 'completed' ? 'Abgeschlossen' : 'Aktiv',
                        style: TextStyle(
                          fontSize: 10,
                          color: status == 'completed' ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _SessionDetailScreen(
                      sessionId: sessions[index].id,
                      userId: user.uid,
                      childId: child.id,
                      topic: topic,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(dateDay).inDays;

    if (diff == 0) {
      return 'Heute ${date.hour}:${date.minute.toString().padLeft(2, '0')} Uhr';
    }
    if (diff == 1) {
      return 'Gestern ${date.hour}:${date.minute.toString().padLeft(2, '0')} Uhr';
    }
    return '${date.day}.${date.month}.${date.year}';
  }
}

class _SessionDetailScreen extends StatelessWidget {
  final String sessionId;
  final String userId;
  final String childId;
  final String topic;

  const _SessionDetailScreen({
    required this.sessionId,
    required this.userId,
    required this.childId,
    required this.topic,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(topic),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('children')
            .doc(childId)
            .collection('tutor_sessions')
            .doc(sessionId)
            .collection('messages')
            .orderBy('timestamp', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('Keine Nachrichten'));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final msg = docs[i].data() as Map<String, dynamic>;
              final isUser = msg['isUser'] as bool? ?? false;
              final text = msg['text'] as String? ?? '';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.deepPurple : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// TAB 3: STATISTIK — visuell wie Eltern-Dashboard
// ============================================================================

class _StatisticsTab extends ConsumerWidget {
  final ChildModel child;

  const _StatisticsTab({required this.child});

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
        final successRate =
        totalQuizzes > 0 ? ((perfectQuizzes / totalQuizzes) * 100).toInt() : 0;

        // XP im aktuellen Level berechnen
        int currentLevelXP = xp;
        for (int i = 1; i < level; i++) {
          currentLevelXP -= XPService.calculateXPForLevel(i);
        }
        final xpForNextLevel = XPService.calculateXPForLevel(level);
        final xpProgress = (currentLevelXP / xpForNextLevel).clamp(0.0, 1.0);
        final xpPercentage = (xpProgress * 100).toInt();

        final formattedTime = _formatShort(totalSeconds);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Übersicht Kacheln ────────────────────────────────────
              const _SectionHeader(icon: Icons.dashboard, title: 'Übersicht'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _GradientStatCard(
                      icon: Icons.emoji_events,
                      label: 'Level',
                      value: '$level',
                      subtitle: 'Erreicht',
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _GradientStatCard(
                      icon: Icons.auto_graph,
                      label: 'Gesamt XP',
                      value: '$xp',
                      subtitle: 'Gesammelt',
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _GradientStatCard(
                      icon: Icons.stars,
                      label: 'Sterne',
                      value: '$stars',
                      subtitle: 'Verdient',
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _GradientStatCard(
                      icon: Icons.timer,
                      label: 'Lernzeit',
                      value: formattedTime,
                      subtitle: 'Gesamt',
                      color: Colors.green,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Level-Fortschritt ────────────────────────────────────
              const _SectionHeader(
                  icon: Icons.trending_up, title: 'Level-Fortschritt'),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _LevelBadge(level: level),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$xpPercentage%',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              Text('bis Level ${level + 1}',
                                  style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: xpProgress,
                          minHeight: 14,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.deepPurple),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Level $level',
                              style: TextStyle(color: Colors.grey[700])),
                          Text(
                            '${xpForNextLevel - currentLevelXP} XP fehlen',
                            style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Lernzeit ─────────────────────────────────────────────
              const _SectionHeader(icon: Icons.schedule, title: 'Lernzeit'),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.green.withOpacity(0.3), width: 2),
                        ),
                        child: _LearningTimeDisplay(totalSeconds: totalSeconds),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.local_fire_department,
                              label: 'Streak',
                              value: '$streak Tage 🔥',
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.quiz,
                              label: 'Quizze',
                              value: '$totalQuizzes gespielt',
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Streak ──────────────────────────────────────────────
              const _SectionHeader(
                  icon: Icons.local_fire_department, title: 'Lern-Streak'),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
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
                      const Icon(Icons.local_fire_department,
                          size: 48, color: Colors.white),
                      const SizedBox(height: 8),
                      Text(
                        '$streak',
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text('Tage Lern-Streak',
                          style: TextStyle(fontSize: 16, color: Colors.white)),
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
              ),

              const SizedBox(height: 24),

              // ── Quiz-Statistiken ────────────────────────────────────
              const _SectionHeader(icon: Icons.quiz, title: 'Quiz-Statistiken'),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.assignment_turned_in,
                              label: 'Absolviert',
                              value: '$totalQuizzes',
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.stars,
                              label: 'Perfekt',
                              value: '$perfectQuizzes ✨',
                              color: Colors.amber,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.percent,
                              label: 'Erfolg',
                              value: '$successRate%',
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      if (totalQuizzes > 0) ...[
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: perfectQuizzes / totalQuizzes,
                            minHeight: 10,
                            backgroundColor: Colors.grey.shade200,
                            valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.amber),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$perfectQuizzes von $totalQuizzes perfekt gelöst',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            'Mach dein erstes Quiz, um Statistiken zu sehen!',
                            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Lernfortschritt Platzhalter ─────────────────────────
              const _SectionHeader(
                  icon: Icons.bar_chart, title: 'Lernfortschritt'),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.insert_chart_outlined,
                          size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'Folgt in Kürze',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Detaillierte Lernkurven kommen bald',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }

  String _formatShort(int totalSeconds) {
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (days > 0) return '${days}T ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}min';
    return '${minutes}min';
  }
}

// ============================================================================
// LERNZEIT DETAIL-ANZEIGE (Tage / Stunden / Minuten / Sekunden)
// ============================================================================

class _LearningTimeDisplay extends StatelessWidget {
  final int totalSeconds;

  const _LearningTimeDisplay({required this.totalSeconds});

  @override
  Widget build(BuildContext context) {
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (days > 0) ...[
              _TimeBlock(value: days, label: days == 1 ? 'Tag' : 'Tage'),
              _TimeSep(),
            ],
            _TimeBlock(value: hours, label: 'Std'),
            _TimeSep(),
            _TimeBlock(value: minutes, label: 'Min'),
            _TimeSep(),
            _TimeBlock(value: secs, label: 'Sek', small: true),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Gesamte Lernzeit',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final int value;
  final String label;
  final bool small;

  const _TimeBlock({required this.value, required this.label, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: small ? 10 : 14,
            vertical: small ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: small ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }
}

class _TimeSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 4, right: 4),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.green.shade400,
        ),
      ),
    );
  }
}

// ============================================================================
// LIVE LERNZEIT CARD (Home Tab) — Tage / Stunden / Minuten / Sekunden
// ============================================================================

class _LiveLearningTimeCard extends ConsumerWidget {
  final String childId;

  const _LiveLearningTimeCard({required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(childId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final totalSeconds = data?['totalLearningSeconds'] as int? ?? 0;

        final days = totalSeconds ~/ 86400;
        final hours = (totalSeconds % 86400) ~/ 3600;
        final minutes = (totalSeconds % 3600) ~/ 60;
        final secs = totalSeconds % 60;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blue.shade700],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                '⏱️ Deine Lernzeit',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (days > 0) ...[
                    _HomeTimeUnit(value: days, label: days == 1 ? 'Tag' : 'Tage'),
                    _HomeSep(),
                  ],
                  _HomeTimeUnit(value: hours, label: 'Std'),
                  _HomeSep(),
                  _HomeTimeUnit(value: minutes, label: 'Min'),
                  _HomeSep(),
                  _HomeTimeUnit(value: secs, label: 'Sek', small: true),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeTimeUnit extends StatelessWidget {
  final int value;
  final String label;
  final bool small;

  const _HomeTimeUnit(
      {required this.value, required this.label, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: small ? 10 : 14,
            vertical: small ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: small ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }
}

class _HomeSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16, left: 4, right: 4),
      child: Text(':',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white54)),
    );
  }
}

// ============================================================================
// HILFS-WIDGETS
// ============================================================================

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// Gradient-Kachel wie im Eltern-Dashboard
class _GradientStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;

  const _GradientStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.12), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            Text(subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

/// Info-Kachel für Detail-Bereiche
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color),
          ),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

/// Level-Badge
class _LevelBadge extends StatelessWidget {
  final int level;

  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.deepPurple, Colors.purple],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, color: Colors.amber, size: 28),
          const SizedBox(height: 4),
          Text(
            'Level $level',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STATUS HEADER
// ============================================================================

class _StatusHeader extends StatelessWidget {
  final ChildModel child;

  const _StatusHeader({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple, Colors.purple.shade700],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Level ${child.level}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${child.stars} ⭐ Sterne',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
              const Icon(Icons.emoji_events, color: Colors.amber, size: 50),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'XP: ${child.xp} / ${child.xpToNextLevel}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: child.xpProgress,
                  minHeight: 12,
                  backgroundColor: Colors.white24,
                  valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SUBJECT TILE
// ============================================================================

class _SubjectTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SubjectTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}