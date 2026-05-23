import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_screen.dart';
import 'package:lerndex/src/features/rewards/data/system_rewards_initializer.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';
import 'package:lerndex/src/features/rewards/presentation/rewards_screen.dart';
import 'rewards_count_provider.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/avatar_settings_sheet.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/statistics_tab.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/tutor_history_tab.dart';
import 'package:lerndex/src/features/tutor/presentation/tutor_provider.dart';
import 'package:lerndex/src/features/tutor/presentation/tutor_screen.dart';
import '../subject_config.dart';
import 'dashboard_theme.dart';
import 'dashboard_theme_provider.dart';
import 'theme_picker_sheet.dart';

// ============================================================================
// SECONDARY DASHBOARD – Klasse 5–13
//
// Design-Prinzipien:
// • Modern & clean – kein Kinderspielzeug-Feeling
// • Persönlich: Farbtheme + Hintergrundbild (aus Galerie)
// • Statistiken prominent sichtbar
// • Dezente Animationen, scharfe Typografie
// • Schüler spüren: "Das ist mein Bereich"
// ============================================================================

class SecondaryDashboardScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const SecondaryDashboardScreen({super.key, required this.child});

  @override
  ConsumerState<SecondaryDashboardScreen> createState() =>
      _SecondaryDashboardScreenState();
}

class _SecondaryDashboardScreenState
    extends ConsumerState<SecondaryDashboardScreen>
    with SingleTickerProviderStateMixin {
  int _currentTab = 0; // 0=Home, 1=Belohnungen, 2=Verlauf, 3=Statistik

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Onboarding einmalig anzeigen

    // Systembelohnungen (Achievements) sicherstellen –
    // falls das Kind noch keine hat oder neue hinzugekommen sind.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authStateChangesProvider).value;
      if (user != null) {
        SystemRewardsInitializer().addMissingSystemRewards(
          userId: user.uid,
          childId: widget.child.id,
        );
      }
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();

    // ✅ FIX: activeChildProvider watchen damit Level-Änderungen (z.B. Tutor-
    // Freischaltung bei Level 2) sofort im FAB und _openTutor() ankommen.
    // Falls der Provider null ist (Eltern-View), auf widget.child zurückfallen.
    final activeChild = ref.watch(activeChildProvider);
    final child = activeChild ?? widget.child;

    final themeIds = (userId: user.uid, childId: widget.child.id);
    final themeState = ref.watch(dashboardThemeProvider(themeIds));
    final theme = themeState.theme;
    final rewardsCount =
        ref.watch(availableRewardsCountProvider).valueOrNull ?? 0;

    // Auf Navigation-Signal vom Quiz lauschen
    ref.listen<bool>(navigateToRewardsTabProvider, (_, shouldNavigate) {
      if (shouldNavigate) {
        ref.read(navigateToRewardsTabProvider.notifier).state = false;
        setState(() => _currentTab = 1);
      }
    });

    return PopScope(
      canPop: _currentTab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentTab != 0) setState(() => _currentTab = 0);
      },
      child: Theme(
        // Lokales Theme-Override für diesen Screen
        data: _buildThemeData(theme),
        child: Scaffold(
          backgroundColor: theme.background,
          appBar: _buildAppBar(theme, user.uid),
          body: FadeTransition(
            opacity: _fadeAnim,
            child: _buildBody(theme, user.uid),
          ),
          floatingActionButton: _buildTutorFab(theme, child),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: _buildBottomNav(theme, rewardsCount),
        ),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(DashboardThemeData theme, String userId) {
    return AppBar(
      backgroundColor: theme.primary,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: theme.isDark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: theme.isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarColor: theme.primary,
      ),
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_rounded,
          color: theme.onPrimary.withOpacity(0.9),
          size: 20,
        ),
        onPressed: () {
          if (_currentTab != 0) {
            setState(() => _currentTab = 0);
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
      title: Text(
        _appBarTitle(),
        style: TextStyle(
          color: theme.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 17,
          letterSpacing: 0.3,
        ),
      ),
      actions: [
        // Theme-Picker Button (nur auf Home-Tab)
        if (_currentTab == 0)
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.palette_outlined,
                color: theme.onPrimary,
                size: 18,
              ),
            ),
            onPressed: () => _showThemePicker(),
            tooltip: 'Design anpassen',
          ),
        // Avatar
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () => _showAvatarSettings(),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: theme.primary.withOpacity(0.6),
                backgroundImage: widget.child.selectedAvatar != null
                    ? AssetImage(
                        'assets/images/${widget.child.selectedAvatar}.png',
                      )
                    : null,
                child: widget.child.selectedAvatar == null
                    ? Text(
                        widget.child.name[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: theme.onPrimary,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(DashboardThemeData theme, String userId) {
    final themeIds = (userId: userId, childId: widget.child.id);
    final bgUrl = ref
        .watch(dashboardThemeProvider(themeIds))
        .backgroundImageUrl;

    // Hintergrundbild-Wrapper (nur auf Home-Tab)
    if (_currentTab == 0 && bgUrl != null) {
      return Stack(
        children: [
          // Hintergrundbild
          Positioned.fill(
            child: _BackgroundImage(
              url: bgUrl,
              fallbackColor: theme.background,
            ),
          ),
          // Dunkel-Overlay für Lesbarkeit
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(theme.isDark ? 0.65 : 0.45),
            ),
          ),
          _buildTabContent(theme),
        ],
      );
    }

    return _buildTabContent(theme);
  }

  Widget _buildTabContent(DashboardThemeData theme) {
    switch (_currentTab) {
      case 0:
        return _SecondaryHomeTab(child: widget.child, theme: theme);
      case 1:
        return RewardsScreen(theme: theme);
      case 2:
        return TutorHistoryTab(child: widget.child);
      case 3:
        return StatisticsTab(child: widget.child);
      default:
        return _SecondaryHomeTab(child: widget.child, theme: theme);
    }
  }

  // ── Tutor FAB ─────────────────────────────────────────────────────────────

  Widget _buildTutorFab(DashboardThemeData theme, ChildModel child) {
    final isLocked = child.level < 2;
    return SizedBox(
      width: 62,
      height: 62,
      child: FloatingActionButton(
        heroTag: 'tutor_fab_secondary',
        onPressed: () => _openTutor(child),
        backgroundColor: isLocked ? Colors.grey.shade400 : theme.primary,
        elevation: 8,
        shape: const CircleBorder(),
        tooltip: isLocked ? 'Tutor ab Level 2 verfügbar' : 'KI-Tutor',
        child: isLocked
            ? const Icon(Icons.lock_rounded, color: Colors.white, size: 26)
            : ClipOval(
                child: Image.asset(
                  'assets/images/lerndex_logo.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.school_rounded,
                    color: theme.onPrimary,
                    size: 28,
                  ),
                ),
              ),
      ),
    );
  }

  // ── Bottom Nav ────────────────────────────────────────────────────────────

  Widget _buildBottomNav(DashboardThemeData theme, int rewardsCount) {
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(
          top: BorderSide(color: theme.primary.withOpacity(0.15), width: 1),
        ),
      ),
      child: BottomAppBar(
        color: Colors.transparent,
        elevation: 0,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SecondaryNavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Start',
                selected: _currentTab == 0,
                theme: theme,
                onTap: () => setState(() => _currentTab = 0),
              ),
              _SecondaryNavItem(
                icon: Icons.card_giftcard_outlined,
                activeIcon: Icons.card_giftcard_rounded,
                label: 'Belohnungen',
                selected: _currentTab == 1,
                theme: theme,
                badgeCount: rewardsCount,
                onTap: () => setState(() => _currentTab = 1),
              ),
              const SizedBox(width: 56), // FAB-Platz
              _SecondaryNavItem(
                icon: Icons.history_outlined,
                activeIcon: Icons.history_rounded,
                label: 'Verlauf',
                selected: _currentTab == 2,
                theme: theme,
                onTap: () => setState(() => _currentTab = 2),
              ),
              _SecondaryNavItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart_rounded,
                label: 'Statistik',
                selected: _currentTab == 3,
                theme: theme,
                onTap: () => setState(() => _currentTab = 3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _appBarTitle() {
    switch (_currentTab) {
      case 0:
        return widget.child.name;
      case 1:
        return 'Belohnungen';
      case 2:
        return 'Tutor-Verlauf';
      case 3:
        return 'Statistiken';
      default:
        return widget.child.name;
    }
  }

  ThemeData _buildThemeData(DashboardThemeData t) {
    return ThemeData(
      brightness: t.isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme(
        brightness: t.isDark ? Brightness.dark : Brightness.light,
        primary: t.primary,
        onPrimary: t.onPrimary,
        secondary: t.secondary,
        onSecondary: t.onPrimary,
        error: Colors.red,
        onError: Colors.white,
        surface: t.surface,
        onSurface: t.onSurface,
      ),
      scaffoldBackgroundColor: t.background,
      cardColor: t.surface,
    );
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ThemePickerSheet(),
    );
  }

  void _showAvatarSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AvatarSettingsSheet(child: widget.child),
    );
  }

  Future<void> _openTutor(ChildModel child) async {
    if (child.level < 2) {
      _showTutorLockedDialog(child);
      return;
    }
    ref.read(tutorFreshChatProvider.notifier).state = true;
    ref.invalidate(tutorProviderFamily(child.id));
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutorScreen()),
    );
  }

  void _showTutorLockedDialog(ChildModel child) {
    final theme = ref
        .read(
          dashboardThemeProvider((
            userId: ref.read(authStateChangesProvider).value?.uid ?? '',
            childId: widget.child.id,
          )),
        )
        .theme;
    final xpNeeded = child.xpToNextLevel;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: theme.surface,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🔒', style: TextStyle(fontSize: 38)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tutor noch gesperrt',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Erreiche Level 2, um den KI-Tutor freizuschalten. Noch $xpNeeded XP! 🚀',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: theme.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚡', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      'Noch $xpNeeded XP bis Level 2',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: theme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Weiter lernen! 💪',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
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
// SECONDARY HOME TAB
// ============================================================================

class _SecondaryHomeTab extends ConsumerWidget {
  final ChildModel child;
  final DashboardThemeData theme;

  const _SecondaryHomeTab({required this.child, required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    final subjects = getSubjectsForChild(child);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero Header ───────────────────────────────────────────────
          _SecondaryHeroHeader(child: child, theme: theme, userId: user?.uid),
          const SizedBox(height: 24),

          // ── Schnellstats ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _QuickStatsRow(
              child: child,
              theme: theme,
              userId: user?.uid,
            ),
          ),
          const SizedBox(height: 14),

          // ── Fächer-Titel ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Deine Fächer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.onSurface,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Fächer-Grid ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
              ),
              itemCount: subjects.length,
              itemBuilder: (context, i) => _ModernSubjectCard(
                config: subjects[i],
                theme: theme,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(subject: subjects[i].subject),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ── Hero Header ───────────────────────────────────────────────────────────────

class _SecondaryHeroHeader extends ConsumerWidget {
  final ChildModel child;
  final DashboardThemeData theme;
  final String? userId;

  const _SecondaryHeroHeader({
    required this.child,
    required this.theme,
    this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId == null) {
      return _buildContent(child.xp, child.level);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(child.id)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final xp = data?['xp'] as int? ?? child.xp;
        final level = data?['level'] as int? ?? child.level;
        return _buildContent(xp, level);
      },
    );
  }

  Widget _buildContent(int xp, int level) {
    final xpForLevel = XPService.calculateXPForLevel(level);
    final xpInLevel = XPService.calculateXPInCurrentLevel(xp, level);
    final progress = (xpInLevel / xpForLevel).clamp(0.0, 1.0);
    final rank = XPService.getRankForLevel(level);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primary.withOpacity(0.95),
            theme.secondary.withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rang + Schulinfo
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(rank.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 5),
                    Text(
                      rank.title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Klasse ${child.grade} · ${child.schoolType}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stats-Zeile
          Row(
            children: [
              _HeaderStat(label: 'Level', value: '$level', theme: theme),
              const SizedBox(width: 24),
              _HeaderStat(label: 'XP', value: '$xp ⚡', theme: theme),
              const SizedBox(width: 24),
              _HeaderStat(
                label: 'XP',
                value: '$xpInLevel / $xpForLevel',
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // XP-Fortschrittsbalken
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final DashboardThemeData theme;

  const _HeaderStat({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ── Schnellstats ──────────────────────────────────────────────────────────────

class _QuickStatsRow extends ConsumerWidget {
  final ChildModel child;
  final DashboardThemeData theme;
  final String? userId;

  const _QuickStatsRow({required this.child, required this.theme, this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId == null) return _buildRow(0, 0, 0);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(child.id)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final streak = data?['streak'] as int? ?? 0;
        final totalQuizzes = data?['totalQuizzes'] as int? ?? 0;
        final totalSeconds = data?['totalLearningSeconds'] as int? ?? 0;
        return _buildRow(streak, totalQuizzes, totalSeconds);
      },
    );
  }

  Widget _buildRow(int streak, int quizzes, int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final timeStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Row(
      children: [
        Expanded(
          child: _QuickStatCard(
            icon: Icons.local_fire_department_rounded,
            value: '$streak',
            label: streak == 1 ? 'Tag Streak' : 'Tage Streak',
            color: Colors.orange,
            theme: theme,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickStatCard(
            icon: Icons.quiz_rounded,
            value: '$quizzes',
            label: 'Quizze',
            color: theme.primary,
            theme: theme,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickStatCard(
            icon: Icons.timer_rounded,
            value: timeStr,
            label: 'Lernzeit',
            color: Colors.teal,
            theme: theme,
          ),
        ),
      ],
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final DashboardThemeData theme;

  const _QuickStatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: theme.onSurface,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.onSurface.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Moderne Fach-Karte (Klasse 5+) ───────────────────────────────────────────
// Kompakte 3-Spalten-Kachel mit Kreis-Icon-Akzent (inspiriert vom
// Grundschul-Design), aber clean & reifer – kein Kinder-Feeling.

class _ModernSubjectCard extends StatefulWidget {
  final SubjectConfig config;
  final DashboardThemeData theme;
  final VoidCallback onTap;

  const _ModernSubjectCard({
    required this.config,
    required this.theme,
    required this.onTap,
  });

  @override
  State<_ModernSubjectCard> createState() => _ModernSubjectCardState();
}

class _ModernSubjectCardState extends State<_ModernSubjectCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.config.gradientColors.first;
    final accentColor = widget.config.gradientColors.last;

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          decoration: BoxDecoration(
            color: widget.theme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primaryColor.withOpacity(0.30),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Dekorativer Kreis oben rechts – sichtbar, farbig
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Kleiner Akzent-Kreis unten links
              Positioned(
                left: -10,
                bottom: -10,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // Inhalt
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Icon-Kreis – nimmt Großteil der Kachel ein
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.config.gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withOpacity(0.45),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          widget.config.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),

                    // Fachname + Pfeil-Kreis
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            widget.config.title,
                            style: TextStyle(
                              color: widget.theme.onSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: widget.config.gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 11,
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

// ── Secondary Nav Item ────────────────────────────────────────────────────────

class _SecondaryNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final DashboardThemeData theme;
  final VoidCallback onTap;
  final int badgeCount;

  const _SecondaryNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  color: selected
                      ? theme.primary
                      : theme.onSurface.withOpacity(0.4),
                  size: 22,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 15,
                        minHeight: 15,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
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
                color: selected
                    ? theme.primary
                    : theme.onSurface.withOpacity(0.4),
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hintergrundbild Widget (lokal oder remote) ────────────────────────────────

class _BackgroundImage extends StatelessWidget {
  final String url;
  final Color fallbackColor;

  const _BackgroundImage({required this.url, required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    // Lokale Datei (file://-Pfad)
    if (url.startsWith('file://')) {
      final path = url.replaceFirst('file://', '');
      final file = File(path);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: fallbackColor),
      );
    }
    // Netzwerk-URL (Fallback für alte Einträge)
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: fallbackColor),
    );
  }
}
