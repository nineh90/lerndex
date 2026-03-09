import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/profile_repository.dart';
import 'live_child_stat_card.dart';
import '../../auth/data/auth_repository.dart';
import 'settings_screen.dart';
import '../../auth/presentation/login_screen.dart';
import '../../../tutorial_provider.dart';
import '../../../tutorial_overlay.dart';

/// Haupt-Dashboard für Eltern mit Statistiken & Verwaltung
class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends ConsumerState<ParentDashboardScreen> {
  int _selectedIndex = 0;

  // GlobalKeys für Tutorial-Spotlights
  final _addChildNavKey = GlobalKey();
  final _childCardAreaKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenListProvider);
    final tutState = ref.watch(tutorialProvider);

    // Spotlight-Key je nach Tutorial-Schritt
    GlobalKey? spotlightKey;
    TooltipPosition tooltipPos = TooltipPosition.above;
    if (tutState.step == TutorialStep.tapAddChild) {
      spotlightKey = _addChildNavKey;
      tooltipPos = TooltipPosition.above;
    } else if (tutState.step == TutorialStep.parentDashboardOverview) {
      spotlightKey = _childCardAreaKey;
      tooltipPos = TooltipPosition.below;
    }

    final bool showOverlay =
        tutState.isActive &&
        tutState.isVisible &&
        (tutState.step == TutorialStep.tapAddChild ||
            tutState.step == TutorialStep.addChild ||
            tutState.step == TutorialStep.parentDashboardOverview);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Eltern-Dashboard'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ── Eigentlicher Inhalt ──────────────────────────────────────
          childrenAsync.when(
            data: (children) {
              if (children.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.child_care, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Noch keine Kinder angelegt',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tippe unten auf „Kind hinzufügen"',
                        style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fortschritte & Verwaltung',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${children.length} ${children.length == 1 ? "Kind" : "Kinder"} registriert',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    // Kinder-Karten mit Key für Tutorial-Spotlight
                    SizedBox(
                      key: _childCardAreaKey,
                      child: Column(
                        children: children
                            .map(
                              (child) => LiveChildStatCard(childId: child.id),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Fehler: $e')),
          ),

          // ── Tutorial Overlay ───────────────────────────────────────
          if (showOverlay)
            TutorialOverlay(
              highlightKey: spotlightKey,
              tooltipPosition: tooltipPos,
              onAction: () => _handleTutorialAction(context),
              onSkip: () => ref.read(tutorialProvider.notifier).skip(),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          switch (index) {
            case 0:
              // Tutorial: addChild-Schritt vormerken
              final tutStep = ref.read(tutorialProvider).step;
              if (tutStep == TutorialStep.tapAddChild) {
                ref
                    .read(tutorialProvider.notifier)
                    .setStep(TutorialStep.addChild);
              }
              _showAddChildDialog(context);
              break;
            case 1:
              _showComingSoon(context, 'Abo');
              break;
            case 2:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              break;
            case 3:
              _confirmSignOut(context);
              break;
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: SizedBox(
              key: _addChildNavKey,
              child: const Icon(Icons.person_add),
            ),
            label: 'Kind hinzufügen',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.star_outline),
            label: 'Abo',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Einstellungen',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.logout),
            label: 'Abmelden',
          ),
        ],
      ),
    );
  }

  // ── Tutorial-Aktion ────────────────────────────────────────────────────────

  void _handleTutorialAction(BuildContext context) {
    final step = ref.read(tutorialProvider).step;
    switch (step) {
      case TutorialStep.tapAddChild:
        // Den echten „Kind hinzufügen" Button antippen
        ref.read(tutorialProvider.notifier).setStep(TutorialStep.addChild);
        _showAddChildDialog(context);
        break;
      case TutorialStep.addChild:
        // Nur Info-Schritt, kein aktiver Button-Tap nötig
        break;
      case TutorialStep.parentDashboardOverview:
        // Tutorial abschließen und zurück
        ref.read(tutorialProvider.notifier).nextStep();
        Navigator.of(context).pop();
        break;
      default:
        break;
    }
  }

  // ── Kind hinzufügen ──────────────────────────────────────────────────────
  void _showAddChildDialog(BuildContext screenContext) {
    final nameController = TextEditingController();
    int selectedAge = 6;
    int selectedGrade = 1;
    String selectedSchoolType = 'Grundschule';

    showDialog(
      context: screenContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Neues Kind registrieren'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: selectedAge,
                  decoration: const InputDecoration(
                    labelText: 'Alter',
                    prefixIcon: Icon(Icons.cake_outlined),
                  ),
                  items: List.generate(11, (i) => i + 6)
                      .map(
                        (age) => DropdownMenuItem(
                          value: age,
                          child: Text('$age Jahre'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedAge = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selectedGrade,
                  decoration: const InputDecoration(labelText: 'Klasse'),
                  items: List.generate(8, (i) => i + 1)
                      .map(
                        (g) => DropdownMenuItem(
                          value: g,
                          child: Text('Klasse $g'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedGrade = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedSchoolType,
                  decoration: const InputDecoration(labelText: 'Schulform'),
                  items:
                      [
                            'Grundschule',
                            'Gymnasium',
                            'Realschule',
                            'Hauptschule',
                            'Gesamtschule',
                          ]
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedSchoolType = val!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  showDialog(
                    context: dialogContext,
                    barrierDismissible: false,
                    builder: (_) =>
                        const Center(child: CircularProgressIndicator()),
                  );
                  try {
                    await ref
                        .read(profileRepositoryProvider)
                        .createChild(
                          name: nameController.text,
                          age: selectedAge,
                          grade: selectedGrade,
                          schoolType: selectedSchoolType,
                        );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext); // Loading-Dialog
                      Navigator.pop(dialogContext); // Kind-Dialog

                      // Tutorial: Kind angelegt → Schritt 6 (showChildCard)
                      final tutStep = ref.read(tutorialProvider).step;
                      if (tutStep == TutorialStep.addChild ||
                          tutStep == TutorialStep.tapAddChild) {
                        final tutNotifier = ref.read(tutorialProvider.notifier);
                        tutNotifier.setStep(TutorialStep.showChildCard);
                        tutNotifier.hideOverlay();

                        await Future.delayed(const Duration(milliseconds: 200));

                        if (screenContext.mounted) {
                          // screenContext gehört zum ParentDashboard → poppt ihn korrekt
                          Navigator.of(screenContext).pop();
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                          tutNotifier.showOverlay();
                        }
                        return;
                      }

                      if (screenContext.mounted) {
                        ScaffoldMessenger.of(screenContext).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Kind erfolgreich angelegt!'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(screenContext).showSnackBar(
                        SnackBar(
                          content: Text('❌ Fehler: $e'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Platzhalter „Bald verfügbar" ─────────────────────────────────────────
  void _showComingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Text(feature),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 56, color: Colors.deepPurple),
            const SizedBox(height: 16),
            Text(
              '„$feature" ist bald verfügbar! 🚀',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Dieses Feature befindet sich gerade in Entwicklung und wird in einem zukünftigen Update freigeschaltet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  // ── Abmelden bestätigen ──────────────────────────────────────────────────
  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text('Möchtest du dich wirklich abmelden?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
  }
}
