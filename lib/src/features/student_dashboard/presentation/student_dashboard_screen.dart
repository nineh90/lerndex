import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../rewards/presentation/rewards_screen.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/domain/reward_enums.dart';
import '../../tutor/presentation/tutor_screen.dart';
import '../../tutor/presentation/tutor_provider.dart';
import 'widgets/nav_item.dart';
import 'widgets/home_tab.dart';
import 'widgets/tutor_history_tab.dart';
import 'widgets/statistics_tab.dart';
import 'widgets/avatar_settings_sheet.dart';

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
        return StatisticsTab(child: child);
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
// TAB 0: HOME – NEU GESTALTET (ohne Statistiken)
// ============================================================================

// ============================================================================
// HERO HEADER – nahtlos an AppBar, enthält Level/Sterne/XP
// ============================================================================

// ============================================================================
// TAB 3: STATISTIK – eigene Seite, vollständig erhalten
// ============================================================================

// ============================================================================
// AVATAR CONFIG → ausgelagert in avatar_config.dart
// ============================================================================
