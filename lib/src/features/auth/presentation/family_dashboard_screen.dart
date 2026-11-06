import 'package:flutter/material.dart';
import '../../school/data/parent_link_repository.dart';
import '../../../shared/user_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/auth/presentation/widgets/child_limit_exceeded_screen.dart';
import 'package:lerndex/src/features/auth/presentation/widgets/child_reactivation_screen.dart';
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
import '../../../shared/widgets/parental_gate.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';

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

  /// Kinder, deren Reaktivierung schon angestoßen ist – build() läuft oft,
  /// geschrieben werden soll nur einmal.
  final _reactivationRequested = <String>{};

  @override
  void initState() {
    super.initState();
    // Eltern-Code aus einem gescannten Elternbrief (…/e/CODE), der vor der
    // Anmeldung gemerkt wurde: nachfragen und einlösen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _redeemPendingCode());
  }

  /// Gemerkten Eltern-Code nur nach Rückfrage einlösen: Er könnte von einem
  /// früheren Besuch stammen oder für ein anderes Konto gedacht sein.
  Future<void> _redeemPendingCode() async {
    final repo = ref.read(parentLinkRepositoryProvider);
    final String? code;
    try {
      code = await repo.pendingCode();
    } catch (_) {
      return;
    }
    if (code == null || !mounted) return;
    await repo.clearPending();
    if (!mounted) return;

    final account = ref.read(authStateChangesProvider).value?.email;
    final display = code.length == 8
        ? '${code.substring(0, 4)}-${code.substring(4)}'
        : code;
    // Wer ist das Kind? Ohne Antwort (offline) bleibt es beim Code.
    String child = 'das Kind aus diesem Brief';
    try {
      final p = await repo.preview(code);
      final where = [
        if (p.className.isNotEmpty) 'Klasse ${p.className}',
        if (p.schoolName.isNotEmpty) p.schoolName,
      ].join(', ');
      if (p.firstName.isNotEmpty) {
        child = where.isEmpty ? p.firstName : '${p.firstName} ($where)';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Elternbrief: ${userMessage(e)}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Kind aus der Schule verbinden?'),
        content: Text(
          'Sie haben einen Elternbrief gescannt (Code $display). Soll '
          '$child mit '
          '${account == null ? 'diesem Konto' : 'dem Konto $account'} '
          'verbunden werden? Sie sehen dann die Statistik und können '
          'Belohnungen festlegen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nein'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verbinden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = await repo.link(code);
      messenger.showSnackBar(
        SnackBar(content: Text('$name ist jetzt mit Ihrem Konto verbunden.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Elternbrief: ${userMessage(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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
      error: (_, _) => true,
    );

    // Mit der Schule verbundene Kinder brauchen kein Abo (Schullizenz). Erst
    // für eigene Kinder ist es nötig (das Kinderlimit ohne Abo ist 0).
    final schoolLinks = ref.watch(schoolChildLinksProvider);
    final hasSchoolChildren =
        schoolLinks.value?.isNotEmpty ?? schoolLinks.isLoading;

    // Kein Abo → Paywall als vollständiger Screen (nicht wegklickbar).
    // Parental Gate davor: Kinder können diesen Screen erreichen, Käufe
    // brauchen in Kids-Apps eine Erwachsenen-Schranke (Apple 1.3).
    if (!hasAccess && !hasSchoolChildren) {
      return ParentalGateScreen(
        builder: (_) => const PaywallScreen(canDismiss: false),
      );
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
        children: allChildren,
        allowedCount: childLimit,
      );
    }

    // ── NEU: Upgrade-Check (pausierte Kinder reaktivieren) ──────────────────
    final pausedChildren = allChildren.where((c) => !c.isActive).toList();
    final slotsAvailable = childLimit - activeChildren.length;
    if (pausedChildren.isNotEmpty && slotsAvailable > 0) {
      if (slotsAvailable >= pausedChildren.length) {
        // Alle pausierten Kinder passen rein → automatisch reaktivieren,
        // pro Kind nur einmal (build läuft bei jedem Neuaufbau)
        final todo = pausedChildren
            .where((c) => _reactivationRequested.add(c.id))
            .toList();
        if (todo.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final repo = ref.read(profileRepositoryProvider);
            for (final child in todo) {
              try {
                await repo.reactivateChild(child.id);
              } catch (e) {
                // Beim nächsten Öffnen erneut versuchen
                _reactivationRequested.remove(child.id);
                debugPrint('⚠️ Reaktivierung von ${child.id}: $e');
              }
            }
          });
        }
      } else {
        // Nicht alle passen rein → User wählt welche reaktiviert werden
        return ChildReactivationScreen(
          pausedChildren: pausedChildren,
          slotsAvailable: slotsAvailable,
        );
      }
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
        backgroundColor: AppColors.purple,
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
                      Text(
                        hasSchoolChildren
                            ? 'Schulkinder lernen mit der Karte „Zu Hause '
                                  'lernen“ aus dem Elternbrief. Statistik und '
                                  'Belohnungen finden Sie im Eltern-Dashboard.'
                            : 'Öffne das Eltern-Dashboard, um ein Kind hinzuzufügen',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _openParentDashboard(context, ref),
                        icon: const Icon(Icons.family_restroom),
                        label: const Text('Eltern-Dashboard öffnen'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.purple,
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
                                  ? AppColors.purple
                                  : Colors.grey.shade400,
                              radius: 24,
                              backgroundImage: child.selectedAvatar != null
                                  ? AssetImage(
                                      'assets/images/${child.selectedAvatar}.webp',
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
                                color: AppColors.purple,
                              )
                            : GestureDetector(
                                // Parental Gate vor der Paywall (Kids-App)
                                onTap: () async {
                                  final ok = await showParentalGate(
                                    context,
                                    ref,
                                  );
                                  if (!ok || !context.mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PaywallScreen(canDismiss: true),
                                    ),
                                  );
                                },
                                child: const Icon(
                                  Icons.upgrade,
                                  color: AppColors.purple,
                                ),
                              ),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text(userMessage(e))),
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
                    color: AppColors.purple,
                  ),
                ),

                // ── Info Button ───────────────────────────────────────
                SizedBox(
                  key: _settingsButtonKey,
                  child: _BottomBarButton(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FamilySettingsScreen(),
                      ),
                    ),
                    icon: Icons.info_outline,
                    label: 'Infos',
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

    final hasPin = await ref
        .read(pinRepositoryProvider)
        .hasPinSet(user.ownerUid);
    if (!context.mounted) return;

    if (!hasPin) {
      // Erwachsenen-Schranke VOR der PIN-Ersteinrichtung: sonst könnte sich
      // ein Kind, das zuerst hier tippt, selbst den Elternbereich freischalten.
      final isAdult = await showAdultGateDialog(context);
      if (isAdult != true || !context.mounted) return;

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
