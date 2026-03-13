import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/auth/presentation/widgets/child_limit_exceeded_screen.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/student_dashboard_screen.dart';
import '../data/auth_repository.dart';
import '../data/profile_repository.dart';
import 'active_child_provider.dart';
import '../../parent_dashboard/data/pin_repository.dart';
import '../../parent_dashboard/presentation/pin_setup_dialog.dart';
import '../../parent_dashboard/presentation/pin_input_dialog.dart';
import '../../parent_dashboard/presentation/parent_dashboard_screen.dart';
import '../../parent_dashboard/presentation/family_settings_screen.dart';
import 'widgets/parent_dashboard_button.dart';
import '../../../tutorial_provider.dart';
import '../../../tutorial_overlay.dart';
// NEU: Subscription
import '../../subscription/data/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';

class FamilyDashboardScreen extends ConsumerStatefulWidget {
  const FamilyDashboardScreen({super.key});

  @override
  ConsumerState<FamilyDashboardScreen> createState() =>
      _FamilyDashboardScreenState();
}

class _FamilyDashboardScreenState extends ConsumerState<FamilyDashboardScreen> {
  // GlobalKeys für Tutorial-Spotlights
  final _parentButtonKey = GlobalKey();
  final _settingsButtonKey = GlobalKey();
  final _childListKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenListProvider);
    final pendingRewards = ref.watch(totalPendingRewardsProvider);
    final tutState = ref.watch(tutorialProvider);

    // ── NEU: Abo-Check ─────────────────────────────────────────────────────
    final subscriptionAsync = ref.watch(subscriptionStatusProvider);
    final hasAccess = subscriptionAsync.when(
      data: (s) => s.hasAccess,
      loading: () => true,
      error: (_, __) => true,
    );

    // Kein Abo → Paywall als vollständiger Screen (nicht wegklickbar)
    if (!hasAccess) {
      return const PaywallScreen(canDismiss: false);
    }

    // ── NEU: Downgrade-Check ────────────────────────────────────────────────
    final childLimit = subscriptionAsync.maybeWhen(
      data: (s) => s.childLimit,
      orElse: () => 99,
    );
    final allChildren = childrenAsync.maybeWhen(
      data: (list) => list,
      orElse: () => <ChildModel>[],
    );
    final activeChildren = allChildren.where((c) => c.isActive).toList();
    if (activeChildren.length > childLimit) {
      return ChildLimitExceededScreen(
        children: allChildren, // Alle anzeigen damit Elternteil wählen kann
        allowedCount: childLimit,
      );
    }
    // ── Ende Checks ─────────────────────────────────────────────────────────

    // Aktiven Spotlight-Key je nach Schritt bestimmen
    GlobalKey? spotlightKey;
    TooltipPosition tooltipPos = TooltipPosition.above;

    switch (tutState.step) {
      case TutorialStep.tapParentButton:
        spotlightKey = _parentButtonKey;
        tooltipPos = TooltipPosition.above;
        break;
      case TutorialStep.showChildCard:
        spotlightKey = _childListKey;
        tooltipPos = TooltipPosition.below;
        break;
      default:
        spotlightKey = null;
    }

    final bool showOverlay =
        tutState.isActive &&
        tutState.isVisible &&
        (tutState.step == TutorialStep.familyDashboardIntro ||
            tutState.step == TutorialStep.tapParentButton ||
            tutState.step == TutorialStep.showChildCard);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lerndex'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ── Eigentlicher Inhalt ────────────────────────────────────────
          childrenAsync.when(
            data: (children) {
              if (children.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.child_care,
                        size: 80,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Noch keine Kinder angelegt',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Öffne das Eltern-Dashboard um ein Kind hinzuzufügen',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _openParentDashboard(context, ref),
                        icon: const Icon(Icons.family_restroom),
                        label: const Text('Eltern-Dashboard öffnen'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B21A8),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Aktive Kinder zuerst, inaktive unten
              final sorted = [...children]
                ..sort((a, b) {
                  if (a.isActive == b.isActive) return 0;
                  return a.isActive ? -1 : 1;
                });

              return ListView.builder(
                key: _childListKey,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final child = sorted[index];
                  final isActive = child.isActive;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    // Inaktive Kinder ausgegraut
                    color: isActive ? null : Colors.grey.shade100,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      // Inaktive Kinder nicht klickbar
                      onTap: isActive
                          ? () async {
                              ref
                                  .read(activeChildProvider.notifier)
                                  .select(child);
                              if (context.mounted) {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const StudentDashboardScreen(),
                                  ),
                                );
                                if (context.mounted) {
                                  ref
                                      .read(activeChildProvider.notifier)
                                      .deselect();
                                }
                              }
                            }
                          : null,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: isActive
                                  ? const Color(0xFF6B21A8)
                                  : Colors.grey.shade400,
                              radius: 24,
                              backgroundImage: child.selectedAvatar != null
                                  ? AssetImage(
                                      'assets/images/${child.selectedAvatar}.png',
                                    )
                                  : null,
                              child: child.selectedAvatar == null
                                  ? Text(
                                      child.name[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            // Schloss-Icon auf inaktiven Kindern
                            if (!isActive)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(
                                    Icons.lock,
                                    size: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          child.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isActive
                                ? Colors.black87
                                : Colors.grey.shade500,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              isActive
                                  ? '${child.schoolType} • Klasse ${child.grade}'
                                  : 'Pausiert • Upgrade für Zugriff',
                              style: TextStyle(
                                color: isActive ? null : Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.bolt,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${child.xp} XP • Lvl ${child.level}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.local_fire_department,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${child.streak ?? 0} Tage',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        trailing: isActive
                            ? const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF6B21A8),
                              )
                            : GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PaywallScreen(canDismiss: true),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.upgrade,
                                  color: Color(0xFF6B21A8),
                                ),
                              ),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Fehler: $e')),
          ),

          // ── Tutorial Overlay ───────────────────────────────────────────
          if (showOverlay)
            TutorialOverlay(
              highlightKey: spotlightKey,
              tooltipPosition:
                  tutState.step == TutorialStep.familyDashboardIntro
                  ? TooltipPosition.center
                  : tooltipPos,
              onAction: () => _handleTutorialAction(context, ref),
              onSkip: () => ref.read(tutorialProvider.notifier).skip(),
            ),
        ],
      ),

      // ── Bottom Bar ─────────────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ── Eltern-Dashboard Button ────────────────────────────
                SizedBox(
                  key: _parentButtonKey,
                  child: _BottomBarButton(
                    onTap: () => _openParentDashboard(context, ref),
                    badge: pendingRewards,
                    icon: Icons.family_restroom_rounded,
                    label: 'Eltern-Dashboard',
                    color: const Color(0xFF6B21A8),
                  ),
                ),

                // ── Einstellungen Button ───────────────────────────────
                SizedBox(
                  key: _settingsButtonKey,
                  child: _BottomBarButton(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FamilySettingsScreen(),
                      ),
                    ),
                    icon: Icons.settings_outlined,
                    label: 'Einstellungen',
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Tutorial-Aktionen je nach Schritt ────────────────────────────────────

  void _handleTutorialAction(BuildContext context, WidgetRef ref) {
    final step = ref.read(tutorialProvider).step;
    switch (step) {
      case TutorialStep.familyDashboardIntro:
        ref.read(tutorialProvider.notifier).nextStep();
        break;
      case TutorialStep.tapParentButton:
        _openParentDashboard(context, ref);
        break;
      case TutorialStep.showChildCard:
        ref.read(tutorialProvider.notifier).nextStep();
        _openParentDashboard(context, ref);
        break;
      default:
        break;
    }
  }

  // ── Eltern-Dashboard öffnen ──────────────────────────────────────────────

  Future<void> _openParentDashboard(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    final tutNotifier = ref.read(tutorialProvider.notifier);
    final tutStep = ref.read(tutorialProvider).step;

    // Tutorial: Schritt auf enterPin setzen bevor der Dialog kommt
    if (tutStep == TutorialStep.tapParentButton) {
      tutNotifier.setStep(TutorialStep.enterPin);
    }

    final hasPin = await ref.read(pinRepositoryProvider).hasPinSet(user.uid);
    if (!context.mounted) return;

    if (!hasPin) {
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PinSetupDialog(),
      );
      if (created != true) return;
    }

    if (!context.mounted) return;

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PinInputDialog(),
    );

    if (verified == true && context.mounted) {
      // Tutorial: Nach PIN → Kind hinzufügen
      final currentStep = ref.read(tutorialProvider).step;
      if (currentStep == TutorialStep.enterPin) {
        tutNotifier.setStep(TutorialStep.tapAddChild);
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
      );
      // showOverlay() wird von parent_dashboard_screen.dart aufgerufen
      // nachdem das Kind angelegt und zurücknavigiert wurde.
    }
  }
}

// ── Wiederverwendbarer Bottom-Bar-Button ──────────────────────────────────────
class _BottomBarButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;
  final int badge;

  const _BottomBarButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 26, color: color),
                if (badge > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[700],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
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
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
