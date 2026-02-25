import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../quiz/presentation/quiz_screen.dart';
import '../../rewards/presentation/rewards_screen.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/domain/reward_enums.dart';
import '../../rewards/data/xp_service.dart';
import '../../tutor/presentation/tutor_screen.dart';
import '../../tutor/presentation/tutor_provider.dart';

// Provider: Anzahl der einlösbaren Belohnungen für das aktive Kind
final _availableRewardsCountProvider = StreamProvider<int>((ref) {
  final activeChild = ref.watch(activeChildProvider);
  final userAsync = ref.watch(authStateChangesProvider);
  final user = userAsync.value;

  if (activeChild == null || user == null) return Stream.value(0);

  return ref
      .read(rewardServiceProvider)
      .getRewardsStream(userId: user.uid, childId: activeChild.id)
      .map(
        (rewards) =>
            rewards.where((r) => r.status == RewardStatus.approved).length,
      );
});

// ============================================================================
// DYNAMISCHE FÄCHER-KONFIGURATION
// Basierend auf schoolType + grade des Kindes – einfach erweiterbar
// ============================================================================

class SubjectConfig {
  final String title;
  final String emoji;
  final IconData icon;
  final List<Color> gradientColors;
  final String subject; // Übergabewert an QuizScreen

  const SubjectConfig({
    required this.title,
    required this.emoji,
    required this.icon,
    required this.gradientColors,
    required this.subject,
  });
}

/// Gibt die passenden Fächer für ein Kind zurück
/// Basiert auf schoolType und grade aus ChildModel
List<SubjectConfig> getSubjectsForChild(ChildModel child) {
  final grade = child.grade;
  final schoolType = child.schoolType;

  // ── Grundschule (Klasse 1–4) ─────────────────────────────────────────────
  if (schoolType == 'Grundschule' || grade <= 4) {
    return const [
      SubjectConfig(
        title: 'Mathe',
        emoji: '🔢',
        icon: Icons.calculate_rounded,
        gradientColors: [Color(0xFFFF8C00), Color(0xFFE64A19)],
        subject: 'Mathe',
      ),
      SubjectConfig(
        title: 'Deutsch',
        emoji: '📖',
        icon: Icons.menu_book_rounded,
        gradientColors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
        subject: 'Deutsch',
      ),
      SubjectConfig(
        title: 'Englisch',
        emoji: '🌍',
        icon: Icons.language_rounded,
        gradientColors: [Color(0xFF1E88E5), Color(0xFF039BE5)],
        subject: 'Englisch',
      ),
      SubjectConfig(
        title: 'Sachkunde',
        emoji: '🌿',
        icon: Icons.wb_sunny_rounded,
        gradientColors: [Color(0xFF43A047), Color(0xFF7CB342)],
        subject: 'Sachkunde',
      ),
    ];
  }

  // ── Mittelstufe (Klasse 5–10) ─────────────────────────────────────────────
  if (grade <= 10) {
    return const [
      SubjectConfig(
        title: 'Mathe',
        emoji: '🔢',
        icon: Icons.calculate_rounded,
        gradientColors: [Color(0xFFFF8C00), Color(0xFFE64A19)],
        subject: 'Mathe',
      ),
      SubjectConfig(
        title: 'Deutsch',
        emoji: '✍️',
        icon: Icons.menu_book_rounded,
        gradientColors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
        subject: 'Deutsch',
      ),
      SubjectConfig(
        title: 'Englisch',
        emoji: '🌍',
        icon: Icons.language_rounded,
        gradientColors: [Color(0xFF1E88E5), Color(0xFF039BE5)],
        subject: 'Englisch',
      ),
      SubjectConfig(
        title: 'Biologie',
        emoji: '🧬',
        icon: Icons.biotech_rounded,
        gradientColors: [Color(0xFF26A69A), Color(0xFF00897B)],
        subject: 'Biologie',
      ),
      SubjectConfig(
        title: 'Chemie',
        emoji: '🧪',
        icon: Icons.science_rounded,
        gradientColors: [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
        subject: 'Chemie',
      ),
      SubjectConfig(
        title: 'Physik',
        emoji: '⚡',
        icon: Icons.bolt_rounded,
        gradientColors: [Color(0xFF5C6BC0), Color(0xFF512DA8)],
        subject: 'Physik',
      ),
      SubjectConfig(
        title: 'Geschichte',
        emoji: '🏛️',
        icon: Icons.account_balance_rounded,
        gradientColors: [Color(0xFF8D6E63), Color(0xFF546E7A)],
        subject: 'Geschichte',
      ),
    ];
  }

  // ── Oberstufe (Klasse 11–13) ──────────────────────────────────────────────
  return const [
    SubjectConfig(
      title: 'Mathe',
      emoji: '📐',
      icon: Icons.calculate_rounded,
      gradientColors: [Color(0xFFFF8C00), Color(0xFFE64A19)],
      subject: 'Mathe',
    ),
    SubjectConfig(
      title: 'Deutsch',
      emoji: '✍️',
      icon: Icons.menu_book_rounded,
      gradientColors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
      subject: 'Deutsch',
    ),
    SubjectConfig(
      title: 'Englisch',
      emoji: '🌍',
      icon: Icons.language_rounded,
      gradientColors: [Color(0xFF1E88E5), Color(0xFF039BE5)],
      subject: 'Englisch',
    ),
    SubjectConfig(
      title: 'Chemie',
      emoji: '🧪',
      icon: Icons.science_rounded,
      gradientColors: [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
      subject: 'Chemie',
    ),
    SubjectConfig(
      title: 'Physik',
      emoji: '⚡',
      icon: Icons.bolt_rounded,
      gradientColors: [Color(0xFF3949AB), Color(0xFF1A237E)],
      subject: 'Physik',
    ),
    SubjectConfig(
      title: 'Geschichte',
      emoji: '🏛️',
      icon: Icons.account_balance_rounded,
      gradientColors: [Color(0xFF8D6E63), Color(0xFF546E7A)],
      subject: 'Geschichte',
    ),
  ];
}

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

    final availableRewardsCount =
        ref.watch(_availableRewardsCountProvider).valueOrNull ?? 0;

    return PopScope(
      // System-Back abfangen wenn wir nicht auf Tab 0 sind
      canPop: _currentTab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentTab != 0) {
          setState(() => _currentTab = 0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F3FF),
        appBar: AppBar(
          title: Text(_appBarTitle(activeChild.name)),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_currentTab != 0) {
                // In einem Tab → zurück zu Tab 0 (Home)
                setState(() => _currentTab = 0);
              } else {
                // Auf Tab 0 → wirklich raus aus dem StudentDashboard
                Navigator.of(context).pop();
              }
            },
            tooltip: _currentTab != 0 ? 'Zurück zum Home' : 'Abmelden',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _showAvatarSettings(context, activeChild),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  backgroundImage: activeChild.selectedAvatar != null
                      ? AssetImage(
                          'assets/images/${activeChild.selectedAvatar}.png',
                        )
                      : null,
                  child: activeChild.selectedAvatar == null
                      ? Text(
                          activeChild.name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        body: _buildBody(activeChild),
        floatingActionButton: SizedBox(
          width: 68,
          height: 68,
          child: FloatingActionButton(
            heroTag: 'tutor_fab',
            onPressed: () => _openTutor(context, activeChild),
            backgroundColor: Colors.deepPurple.shade200,
            elevation: 6,
            shape: const CircleBorder(),
            tooltip: 'KI-Tutor öffnen',
            // ── GEÄNDERT: lerndex_logo.png statt Icons.smart_toy ──────────
            child: ClipOval(
              child: Image.asset(
                'assets/images/lerndex_logo.png',
                width: 55,
                height: 55,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.school, color: Colors.white, size: 32),
              ),
            ),
            // ─────────────────────────────────────────────────────────────
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 6,
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
                  badgeCount: availableRewardsCount,
                ),
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
      ),
    );
  }

  Widget _buildBody(ChildModel child) {
    switch (_currentTab) {
      case 0:
        return _HomeTab(child: child);
      case 1:
        return const RewardsScreen();
      case 2:
        return _TutorHistoryTab(child: child);
      case 3:
        return _StatisticsTab(child: child);
      default:
        return _HomeTab(child: child);
    }
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

  void _showAvatarSettings(BuildContext context, ChildModel child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AvatarSettingsSheet(child: child),
    );
  }

  Future<void> _openTutor(BuildContext context, ChildModel child) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutorScreen()),
    );
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
  final int badgeCount;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  color: selected ? Colors.deepPurple : Colors.grey,
                  size: 24,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
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
// TAB 0: HOME – NEU GESTALTET (ohne Statistiken)
// ============================================================================

class _HomeTab extends ConsumerWidget {
  final ChildModel child;

  const _HomeTab({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = getSubjectsForChild(child);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero-Header (nahtlos an AppBar) ─────────────────────────────
          _HeroHeader(child: child),

          // ── Live Lernzeit + Streak ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _LiveLearningTimeCard(childId: child.id),
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
                final s = subjects[index];
                return _PlayfulSubjectTile(
                  config: s,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuizScreen(subject: s.subject),
                    ),
                  ),
                );
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

// ============================================================================
// HERO HEADER – nahtlos an AppBar, enthält Level/Sterne/XP
// ============================================================================

// ============================================================================
// HERO HEADER – nahtlos an AppBar, enthält Level/Sterne/XP
// Live via Firestore-Stream → updated sofort nach Tutor-Session
// ============================================================================

class _HeroHeader extends ConsumerWidget {
  final ChildModel child;

  const _HeroHeader({required this.child});

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
            _HeaderBadge(emoji: '🏆', label: 'Level $level'),
            _HeaderBadge(emoji: rank.emoji, label: rank.title),
            _HeaderBadge(emoji: '⭐', label: '$stars Sterne'),
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

class _HeaderBadge extends StatelessWidget {
  final String emoji;
  final String label;

  const _HeaderBadge({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SPIELERISCHE FACH-KACHEL (NEU GESTALTET)
// ============================================================================

class _PlayfulSubjectTile extends StatefulWidget {
  final SubjectConfig config;
  final VoidCallback onTap;

  const _PlayfulSubjectTile({required this.config, required this.onTap});

  @override
  State<_PlayfulSubjectTile> createState() => _PlayfulSubjectTileState();
}

class _PlayfulSubjectTileState extends State<_PlayfulSubjectTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.94,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.config.gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: widget.config.gradientColors.last.withOpacity(0.4),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Dekorative Kreise im Hintergrund
              Positioned(
                right: -16,
                top: -16,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: -10,
                bottom: -20,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Inhalt
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Emoji oben links
                    Text(
                      widget.config.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                    // Fachname + Pfeil-Button unten
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          widget.config.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 14,
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
      ),
    );
  }
}

// ============================================================================
// LIVE LERNZEIT CARD (Home Tab) – kompaktes Layout mit Streak
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
                color: Colors.black.withOpacity(0.07),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
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
                              border: Border.all(color: Colors.green.shade300),
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
                          _TimeBlock(value: hours, label: 'Std'),
                          _TimeSep(),
                        ],
                        _TimeBlock(value: minutes, label: 'Min'),
                        _TimeSep(),
                        _TimeBlock(value: secs, label: 'Sek', small: true),
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

              // Streak
              Column(
                children: [
                  Row(
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
        );
      },
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final int value;
  final String label;
  final bool small;

  const _TimeBlock({
    required this.value,
    required this.label,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: small ? 8 : 12,
            vertical: small ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: small ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple.shade700,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
      ],
    );
  }
}

class _TimeSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 3, right: 3),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple.shade300,
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 2: TUTOR-VERLAUF (Schüler-Sicht)
// Filtert leere Sessions (messageCount <= 1) und gelöschte (status == 'deleted')
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

        // Leere Sessions (nur Begrüßung) UND gelöschte Sessions ausfiltern
        final visibleDocs = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final msgCount = data['messageCount'] as int? ?? 0;
          final status = data['status'] as String? ?? '';
          return msgCount > 1 && status != 'deleted';
        }).toList();

        if (visibleDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 80,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Noch kein Verlauf',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Starte ein Gespräch mit dem Tutor!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: visibleDocs.length,
          itemBuilder: (context, index) {
            final doc = visibleDocs[index];
            final session = doc.data() as Map<String, dynamic>;
            final startedAt = (session['startedAt'] as Timestamp?)?.toDate();
            final topic = session['detectedTopic'] as String? ?? 'Allgemein';
            final msgCount = session['messageCount'] as int? ?? 0;
            final status = session['status'] as String? ?? 'active';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _SessionDetailScreen(
                      userId: user.uid,
                      childId: child.id,
                      sessionId: doc.id,
                      topic: topic,
                      startedAt: startedAt,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _topicColor(topic).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _topicIcon(topic),
                          color: _topicColor(topic),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topic,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _topicColor(topic),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              startedAt != null
                                  ? _formatDate(startedAt)
                                  : 'Datum unbekannt',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$msgCount Nachrichten',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
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
                                color: status == 'completed'
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'Heute';
    if (dateOnly == yesterday) return 'Gestern';
    return '${date.day}.${date.month}.${date.year}';
  }

  Color _topicColor(String topic) {
    switch (topic) {
      case 'Mathematik':
      case 'Mathe':
        return Colors.orange;
      case 'Deutsch':
        return Colors.red;
      case 'Englisch':
        return Colors.blue;
      case 'Sachkunde':
      case 'Biologie':
        return Colors.green;
      case 'Physik':
        return Colors.indigo;
      case 'Geschichte':
        return Colors.brown;
      default:
        return Colors.deepPurple;
    }
  }

  IconData _topicIcon(String topic) {
    switch (topic) {
      case 'Mathematik':
      case 'Mathe':
        return Icons.calculate_rounded;
      case 'Deutsch':
        return Icons.menu_book_rounded;
      case 'Englisch':
        return Icons.language_rounded;
      case 'Sachkunde':
      case 'Biologie':
        return Icons.science_rounded;
      case 'Physik':
        return Icons.bolt_rounded;
      case 'Geschichte':
        return Icons.account_balance_rounded;
      default:
        return Icons.chat_rounded;
    }
  }
}

// ============================================================================
// SESSION DETAIL – Nachrichtenanzeige
// ============================================================================

class _SessionDetailScreen extends StatelessWidget {
  final String userId;
  final String childId;
  final String sessionId;
  final String topic;
  final DateTime? startedAt;

  const _SessionDetailScreen({
    required this.userId,
    required this.childId,
    required this.sessionId,
    required this.topic,
    this.startedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(topic),
            if (startedAt != null)
              Text(
                '${startedAt!.day}.${startedAt!.month}.${startedAt!.year}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
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
                alignment: isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
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
// TAB 3: STATISTIK – eigene Seite, vollständig erhalten
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
        final successRate = totalQuizzes > 0
            ? (perfectQuizzes / totalQuizzes * 100).round()
            : 0;

        final hours = totalSeconds ~/ 3600;
        final minutes = (totalSeconds % 3600) ~/ 60;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon: Icons.emoji_events,
                title: 'Meine Erfolge',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.star,
                      color: Colors.amber,
                      value: '$stars',
                      label: 'Sterne',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.emoji_events,
                      color: Colors.deepPurple,
                      value: 'Lvl $level',
                      label: 'Level',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.bolt,
                      color: Colors.orange,
                      value: '$xp XP',
                      label: 'Gesamt',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionHeader(
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
              const _SectionHeader(icon: Icons.quiz, title: 'Quiz-Statistiken'),
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
                        child: _InfoTile(
                          icon: Icons.assignment_turned_in,
                          label: 'Absolviert',
                          value: '$totalQuizzes',
                        ),
                      ),
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.workspace_premium,
                          label: 'Perfekt',
                          value: '$perfectQuizzes',
                        ),
                      ),
                      Expanded(
                        child: _InfoTile(
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
              const _SectionHeader(icon: Icons.timer, title: 'Lernzeit'),
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

// ============================================================================
// STATISTIK HILFS-WIDGETS
// ============================================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

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
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

// ============================================================================
// AVATAR CONFIG
// ============================================================================

class AvatarConfig {
  final String id; // asset name ohne .png
  final String label; // Anzeigename
  final int requiredLevel; // Level zum Freischalten
  final Color color; // Rarity-Farbe
  final String rarityLabel;
  // Für spätere Payment-Integration:
  // final bool requiresPayment;
  // final String? productId;

  const AvatarConfig({
    required this.id,
    required this.label,
    required this.requiredLevel,
    required this.color,
    required this.rarityLabel,
  });
}

const List<AvatarConfig> kAvatars = [
  AvatarConfig(
    id: 'avatar-common',
    label: 'Common',
    requiredLevel: 1,
    color: Color(0xFF78909C),
    rarityLabel: '⬜ Common',
  ),
  AvatarConfig(
    id: 'avatar-common-1',
    label: 'Common',
    requiredLevel: 1,
    color: Color(0xFF78909C),
    rarityLabel: '⬜ Common',
  ),
  AvatarConfig(
    id: 'avatar-uncommon',
    label: 'Uncommon',
    requiredLevel: 5,
    color: Color(0xFF43A047),
    rarityLabel: '🟩 Uncommon',
  ),
  AvatarConfig(
    id: 'avatar-uncommon-1',
    label: 'Uncommon',
    requiredLevel: 5,
    color: Color(0xFF43A047),
    rarityLabel: '🟩 Uncommon',
  ),
  AvatarConfig(
    id: 'avatar-rare',
    label: 'Rare',
    requiredLevel: 10,
    color: Color(0xFF1E88E5),
    rarityLabel: '🟦 Rare',
  ),
  AvatarConfig(
    id: 'avatar-epic',
    label: 'Epic',
    requiredLevel: 25,
    color: Color(0xFF8E24AA),
    rarityLabel: '🟪 Epic',
  ),
  AvatarConfig(
    id: 'avatar-legendary',
    label: 'Legendary',
    requiredLevel: 50,
    color: Color(0xFFFF8F00),
    rarityLabel: '🟨 Legendary',
  ),
];

// ============================================================================
// AVATAR SETTINGS BOTTOM SHEET
// ============================================================================

class _AvatarSettingsSheet extends ConsumerStatefulWidget {
  final ChildModel child;

  const _AvatarSettingsSheet({required this.child});

  @override
  ConsumerState<_AvatarSettingsSheet> createState() =>
      _AvatarSettingsSheetState();
}

class _AvatarSettingsSheetState extends ConsumerState<_AvatarSettingsSheet> {
  bool _saving = false;

  Future<void> _selectAvatar(AvatarConfig avatar) async {
    if (_saving) return;
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    // Wenn derselbe Avatar nochmal getippt wird → abwählen (null)
    final currentAvatar = ref.read(activeChildProvider)?.selectedAvatar;
    final newValue = currentAvatar == avatar.id ? null : avatar.id;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(widget.child.id)
          .update({'selectedAvatar': newValue});

      ref.read(activeChildProvider.notifier).updateAvatar(newValue);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fehler beim Speichern')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Aktuellen Avatar-Stand live aus dem Provider lesen → Checkmark springt sofort
    final currentAvatar = ref.watch(activeChildProvider)?.selectedAvatar;
    final child = widget.child;
    final screenHeight = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Aktueller Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.deepPurple.shade100,
              backgroundImage: currentAvatar != null
                  ? AssetImage('assets/images/$currentAvatar.png')
                  : null,
              child: currentAvatar == null
                  ? Text(
                      child.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    )
                  : null,
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
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Avatar wählen',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            // Avatar Grid
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: kAvatars.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final avatar = kAvatars[index];
                  final isUnlocked = child.level >= avatar.requiredLevel;
                  final isSelected = currentAvatar == avatar.id;

                  return GestureDetector(
                    onTap: isUnlocked ? () => _selectAvatar(avatar) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? avatar.color
                              : isUnlocked
                              ? avatar.color.withOpacity(0.4)
                              : Colors.grey.shade300,
                          width: isSelected ? 3 : 1.5,
                        ),
                        color: isSelected
                            ? avatar.color.withOpacity(0.1)
                            : Colors.grey.shade50,
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    10,
                                    8,
                                    4,
                                  ),
                                  child: ColorFiltered(
                                    colorFilter: isUnlocked
                                        ? const ColorFilter.mode(
                                            Colors.transparent,
                                            BlendMode.multiply,
                                          )
                                        : const ColorFilter.matrix([
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0,
                                            0,
                                            0,
                                            1,
                                            0,
                                          ]),
                                    child: Image.asset(
                                      'assets/images/${avatar.id}.png',
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.face,
                                        size: 48,
                                        color: avatar.color.withOpacity(
                                          isUnlocked ? 1.0 : 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  avatar.rarityLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isUnlocked
                                        ? avatar.color
                                        : Colors.grey[400],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          // Lock overlay
                          if (!isUnlocked)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withOpacity(0.5),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.lock_rounded,
                                      color: Colors.grey[500],
                                      size: 22,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Lvl ${avatar.requiredLevel}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Ausgewählt-Checkmark
                          if (isSelected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: avatar.color,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}
