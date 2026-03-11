import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/dashboard_mode.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/early_learner_dashboard_screen.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/rewards_count_provider.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/secondary_dashboard_screen.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/secondary_onboarding_screen.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../rewards/presentation/rewards_screen.dart';
import '../../tutor/presentation/tutor_screen.dart';
import '../../tutor/presentation/tutor_provider.dart';
import '../../quiz/data/ai_question_cache_repository.dart';
import '../../quiz/data/quiz_prefetch_service.dart';
import '../../rewards/data/xp_service.dart';
import 'widgets/nav_item.dart';
import 'widgets/home_tab.dart';
import 'widgets/tutor_history_tab.dart';
import 'widgets/statistics_tab.dart';
import 'widgets/avatar_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// Dashboard-Varianten – werden je nach Klassenstufe angezeigt.
// Phase 2 (Klasse 1–2) und Phase 3 (Klasse 5+) sind Placeholder-Screens,
// die schrittweise mit echtem UI befüllt werden.
// ============================================================================

// ============================================================================
// STUDENT DASHBOARD ROUTER
// Wählt das richtige Dashboard anhand der Klassenstufe des Kindes.
// ============================================================================

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState
    extends ConsumerState<StudentDashboardScreen> {
  bool _showOnboarding = false;
  bool _onboardingChecked = false;
  // Letzter bekannter Mode – erkennt Klassenwechsel
  DashboardMode? _lastMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCacheReady();
      _checkOnboarding();
      _checkStreakOnOpen();
    });
  }

  /// Prüft beim Öffnen des Dashboards ob der Streak verfallen ist.
  /// So sieht das Kind sofort den korrekten Streak — nicht erst nach dem nächsten Quiz.
  Future<void> _checkStreakOnOpen() async {
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    if (child == null || user == null) return;

    try {
      final xpService = ref.read(xpServiceProvider);
      final validStreak = await xpService.checkAndResetStreakIfExpired(
        userId: user.uid,
        childId: child.id,
      );

      // Nur updaten wenn sich der Streak geändert hat
      if (validStreak != child.streak && mounted) {
        ref
            .read(activeChildProvider.notifier)
            .update(child.copyWith(streak: validStreak));
        print(
          '🔄 Dashboard: Streak korrigiert von ${child.streak} → $validStreak',
        );
      }
    } catch (e) {
      print('❌ Dashboard: Streak-Check fehlgeschlagen: $e');
    }
  }

  void _ensureCacheReady() {
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    if (child != null && user != null) {
      QuizPrefetchService.prefetchAllSubjects(
        userId: user.uid,
        child: child,
        cache: ref.read(aiQuestionCacheRepositoryProvider),
      );
    }
  }

  Future<void> _checkOnboarding() async {
    final child = ref.read(activeChildProvider);
    if (child == null) return;

    final mode = getDashboardMode(child.grade);
    if (mode == DashboardMode.secondaryLearner) {
      final show = await shouldShowSecondaryOnboarding(child.id);
      if (mounted) {
        setState(() {
          _showOnboarding = show;
          _onboardingChecked = true;
        });
      }
    } else {
      if (mounted) setState(() => _onboardingChecked = true);
    }
  }

  void _handleGradeTransition(ChildModel child, DashboardMode newMode) {
    // Klassenübergang von Grundschule → weiterführend
    if (_lastMode != null &&
        _lastMode != DashboardMode.secondaryLearner &&
        newMode == DashboardMode.secondaryLearner) {
      _lastMode = newMode;
      // Onboarding-Flag zurücksetzen damit neues Dashboard gezeigt wird
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('secondary_onboarding_seen_${child.id}');
      });
      setState(() => _showOnboarding = true);
      return;
    }
    _lastMode = newMode;
  }

  @override
  Widget build(BuildContext context) {
    final activeChild = ref.watch(activeChildProvider);
    if (activeChild == null) return const SizedBox.shrink();
    if (!_onboardingChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final mode = getDashboardMode(activeChild.grade);

    // Klassenübergang prüfen
    if (_lastMode != null && _lastMode != mode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleGradeTransition(activeChild, mode);
      });
    }
    _lastMode = mode;

    // Onboarding für Klasse 5+ (einmalig)
    if (_showOnboarding && mode == DashboardMode.secondaryLearner) {
      return SecondaryOnboardingScreen(
        childName: activeChild.name,
        childId: activeChild.id,
        onDone: () => setState(() => _showOnboarding = false),
      );
    }

    switch (mode) {
      case DashboardMode.earlyLearner:
        return EarlyLearnerDashboardScreen(child: activeChild);
      case DashboardMode.primaryLearner:
        return _PrimaryDashboardScreen(child: activeChild);
      case DashboardMode.secondaryLearner:
        return SecondaryDashboardScreen(child: activeChild);
    }
  }
}

// ============================================================================
// PRIMARY DASHBOARD (Klasse 3–4) – bisher bekanntes Design
// Wurde aus dem alten StudentDashboardScreen hierher verschoben.
// ============================================================================

class _PrimaryDashboardScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const _PrimaryDashboardScreen({required this.child});

  @override
  ConsumerState<_PrimaryDashboardScreen> createState() =>
      _PrimaryDashboardScreenState();
}

class _PrimaryDashboardScreenState
    extends ConsumerState<_PrimaryDashboardScreen> {
  int _currentTab = 0; // 0=Home, 1=Belohnungen, 2=Verlauf, 3=Statistik

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final availableRewardsCount =
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
        if (!didPop && _currentTab != 0) {
          setState(() => _currentTab = 0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F3FF),
        appBar: AppBar(
          title: Text(_appBarTitle(child.name)),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_currentTab != 0) {
                setState(() => _currentTab = 0);
              } else {
                Navigator.of(context).pop();
              }
            },
            tooltip: _currentTab != 0 ? 'Zurück zum Home' : 'Abmelden',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _showAvatarSettings(context, child),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  backgroundImage: child.selectedAvatar != null
                      ? AssetImage('assets/images/${child.selectedAvatar}.png')
                      : null,
                  child: child.selectedAvatar == null
                      ? Text(
                          child.name[0].toUpperCase(),
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
        body: _buildBody(child),
        floatingActionButton: _buildTutorFab(child),
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
                NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Lernen',
                  selected: _currentTab == 0,
                  onTap: () => setState(() => _currentTab = 0),
                ),
                NavItem(
                  icon: Icons.card_giftcard_outlined,
                  activeIcon: Icons.card_giftcard,
                  label: 'Belohnungen',
                  selected: _currentTab == 1,
                  onTap: () => setState(() => _currentTab = 1),
                  badgeCount: availableRewardsCount,
                ),
                const SizedBox(width: 60),
                NavItem(
                  icon: Icons.history_outlined,
                  activeIcon: Icons.history,
                  label: 'Verlauf',
                  selected: _currentTab == 2,
                  onTap: () => setState(() => _currentTab = 2),
                ),
                NavItem(
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
        return HomeTab(child: child);
      case 1:
        return const RewardsScreen();
      case 2:
        return TutorHistoryTab(child: child);
      case 3:
        return StatisticsTab(child: child, useTheme: false);
      default:
        return HomeTab(child: child);
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
      builder: (context) => AvatarSettingsSheet(child: child),
    );
  }

  Widget _buildTutorFab(ChildModel child) {
    final isLocked = child.level < 2;
    return SizedBox(
      width: 68,
      height: 68,
      child: FloatingActionButton(
        heroTag: 'tutor_fab_primary',
        onPressed: () => _openTutor(context, child),
        backgroundColor: isLocked
            ? Colors.grey.shade400
            : Colors.deepPurple.shade200,
        elevation: 6,
        shape: const CircleBorder(),
        tooltip: isLocked ? 'Tutor ab Level 2 verfügbar' : 'KI-Tutor öffnen',
        child: isLocked
            ? const Icon(Icons.lock_rounded, color: Colors.white, size: 28)
            : ClipOval(
                child: Image.asset(
                  'assets/images/lerndex_logo.png',
                  width: 55,
                  height: 55,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.school, color: Colors.white, size: 32),
                ),
              ),
      ),
    );
  }

  Future<void> _openTutor(BuildContext context, ChildModel child) async {
    if (child.level < 2) {
      _showTutorLockedDialog(context, child);
      return;
    }
    ref.read(tutorFreshChatProvider.notifier).state = true;
    ref.invalidate(tutorProviderFamily(child.id));

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutorScreen()),
    );
  }

  void _showTutorLockedDialog(BuildContext context, ChildModel child) {
    final xpForLevel2 = child.xpToNextLevel;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🔒', style: TextStyle(fontSize: 38)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tutor noch gesperrt',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Mach noch $xpForLevel2 XP und erreiche Level 2 – dann schaltest du den KI-Tutor frei! 🚀',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
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
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚡', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      'Noch $xpForLevel2 XP bis Level 2',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple,
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
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
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
