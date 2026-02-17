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
import '../../parent_dashboard/presentation/tutor_history_screen.dart';
import '../../parent_dashboard/presentation/child_statistics_screen.dart';

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
      ),
      body: _buildBody(activeChild),
      // ── FAB: Tutor ────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'tutor_fab',
        onPressed: () => _openTutor(context, activeChild),
        backgroundColor: Colors.deepPurple,
        icon: const Icon(Icons.smart_toy, color: Colors.white),
        label: const Text('Tutor', style: TextStyle(color: Colors.white)),
        tooltip: 'KI-Tutor öffnen',
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
              // Linke Seite
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
              // Rechte Seite
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
        return const _EmbeddedRewardsTab();
      case 2:
        return _TutorHistoryTab(child: activeChild);
      case 3:
        return _StatisticsTab(child: activeChild);
      default:
        return _HomeTab(child: activeChild);
    }
  }

  // Tutor öffnen und nach Schließen den Chat löschen
  Future<void> _openTutor(BuildContext context, ChildModel child) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutorScreen()),
    );

    // ✅ Chat automatisch nach Schließen des Tutors löschen & speichern
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
                fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
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
          // Status-Header
          _StatusHeader(child: child),
          const SizedBox(height: 20),

          // Live Lernzeit
          _LiveLearningTimeCard(childId: child.id),
          const SizedBox(height: 24),

          const Text(
            'Wähle ein Fach zum Lernen:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Fächer-Grid
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => QuizScreen(subject: 'Mathe')),
                ),
              ),
              _SubjectTile(
                title: 'Deutsch',
                icon: Icons.menu_book,
                color: Colors.redAccent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => QuizScreen(subject: 'Deutsch')),
                ),
              ),
              _SubjectTile(
                title: 'Englisch',
                icon: Icons.language,
                color: Colors.blue,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => QuizScreen(subject: 'Englisch')),
                ),
              ),
              _SubjectTile(
                title: 'Sachkunde',
                icon: Icons.wb_sunny,
                color: Colors.green,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => QuizScreen(subject: 'Sachkunde')),
                ),
              ),
            ],
          ),

          // Avatar-Einstellungen Card (kompakt)
          const SizedBox(height: 24),
          _AvatarSettingsCard(child: child),
          const SizedBox(height: 80), // Platz für FAB
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: BELOHNUNGEN (via RewardsScreen embedded)
// ============================================================================

// RewardsScreen bekommt optionalen embedded-Parameter –
// wenn embedded=true, kein eigener AppBar, kein Back-Button
// (Anpassung in rewards_screen.dart nötig – hier Wrapper)

class _EmbeddedRewardsTab extends ConsumerWidget {
  const _EmbeddedRewardsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const RewardsScreen();
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
                Icon(Icons.chat_bubble_outline,
                    size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'Noch kein Verlauf',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Starte ein Gespräch mit dem Tutor!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                ),
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
            final startedAt =
            (session['startedAt'] as Timestamp?)?.toDate();
            final topic = session['detectedTopic'] as String? ?? 'Allgemein';
            final msgCount = session['messageCount'] as int? ?? 0;
            final status = session['status'] as String? ?? 'active';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.deepPurple.shade100,
                  child: const Icon(Icons.chat,
                      color: Colors.deepPurple, size: 20),
                ),
                title: Text(
                  topic,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  startedAt != null
                      ? _formatDate(startedAt)
                      : 'Datum unbekannt',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$msgCount Nachrichten',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: status == 'completed'
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status == 'completed'
                            ? 'Abgeschlossen'
                            : 'Aktiv',
                        style: TextStyle(
                          fontSize: 10,
                          color: status == 'completed'
                              ? Colors.green
                              : Colors.orange,
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
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Heute ${date.hour}:${date.minute.toString().padLeft(2, '0')} Uhr';
    if (diff.inDays == 1) return 'Gestern';
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
          if (docs.isEmpty) {
            return const Center(child: Text('Keine Nachrichten'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final msg = docs[i].data() as Map<String, dynamic>;
              final isUser = msg['isUser'] as bool? ?? false;
              final text = msg['text'] as String? ?? '';

              return Align(
                alignment:
                isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Colors.deepPurple
                        : Colors.grey.shade200,
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
// TAB 3: STATISTIK
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
        final hours = totalSeconds ~/ 3600;
        final minutes = (totalSeconds % 3600) ~/ 60;
        final streak = data?['streak'] as int? ?? 0;
        final totalQuizzes = data?['totalQuizzes'] as int? ?? 0;
        final perfectQuizzes = data?['perfectQuizzes'] as int? ?? 0;
        final xp = data?['xp'] as int? ?? child.xp;
        final level = data?['level'] as int? ?? child.level;
        final stars = data?['stars'] as int? ?? child.stars;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Level & XP ─────────────────────────────────────────
              _StatCard(
                title: '🏆 Level & XP',
                children: [
                  _StatRow(label: 'Aktuelles Level', value: 'Level $level'),
                  _StatRow(label: 'Gesamt XP', value: '$xp XP'),
                  _StatRow(label: 'Sterne', value: '$stars ⭐'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: child.xpProgress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.amber),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${child.xp} / ${child.xpToNextLevel} XP bis Level ${level + 1}',
                    style:
                    TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Lernzeit ───────────────────────────────────────────
              _StatCard(
                title: '⏱️ Lernzeit',
                children: [
                  _StatRow(
                    label: 'Gesamt gelernt',
                    value: hours > 0
                        ? '${hours}h ${minutes}min'
                        : '${minutes} Minuten',
                  ),
                  _StatRow(label: 'Streak', value: '$streak 🔥 Tage'),
                ],
              ),
              const SizedBox(height: 16),

              // ── Quiz-Statistiken ────────────────────────────────────
              _StatCard(
                title: '🎯 Quiz-Statistiken',
                children: [
                  _StatRow(label: 'Quizze gespielt', value: '$totalQuizzes'),
                  _StatRow(
                      label: 'Perfekte Quizze', value: '$perfectQuizzes ✨'),
                  if (totalQuizzes > 0)
                    _StatRow(
                      label: 'Erfolgsrate',
                      value:
                      '${((perfectQuizzes / totalQuizzes) * 100).toStringAsFixed(0)}%',
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Platzhalter ─────────────────────────────────────────
              _StatCard(
                title: '📈 Lernfortschritt',
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.bar_chart,
                              size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          Text(
                            'Folgt in Kürze',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 80), // Platz für FAB
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _StatCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ============================================================================
// AVATAR-EINSTELLUNGEN CARD (Platzhalter + zukünftig)
// ============================================================================

class _AvatarSettingsCard extends StatelessWidget {
  final ChildModel child;

  const _AvatarSettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: Colors.deepPurple.shade100,
          child: Text(
            child.name[0].toUpperCase(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
        ),
        title: const Text('Avatar anpassen',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Folgt in Kürze',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎨 Avatar-Anpassung folgt in Kürze!'),
              duration: Duration(seconds: 2),
            ),
          );
        },
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
                  Text(
                    '${child.stars} ⭐ Sterne',
                    style: const TextStyle(color: Colors.white70),
                  ),
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
// LIVE LERNZEIT CARD
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
        final data =
        snapshot.data?.data() as Map<String, dynamic>?;
        final totalSeconds =
            data?['totalLearningSeconds'] as int? ?? 0;
        final hours = totalSeconds ~/ 3600;
        final minutes = (totalSeconds % 3600) ~/ 60;

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
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hours > 0) ...[
                    _TimeUnit(value: hours, label: hours == 1 ? 'Stunde' : 'Stunden'),
                    const SizedBox(width: 16),
                  ],
                  _TimeUnit(
                      value: minutes,
                      label: minutes == 1 ? 'Minute' : 'Minuten'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimeUnit extends StatelessWidget {
  final int value;
  final String label;

  const _TimeUnit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
              fontSize: 12, color: Colors.white),
        ),
      ],
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
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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