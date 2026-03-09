import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class FamilyDashboardScreen extends ConsumerWidget {
  const FamilyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenAsync = ref.watch(childrenListProvider);
    final pendingRewards = ref.watch(totalPendingRewardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lerndex'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: childrenAsync.when(
        data: (children) {
          if (children.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.child_care, size: 80, color: Colors.grey),
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

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: children.length,
            itemBuilder: (context, index) {
              final child = children[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    ref.read(activeChildProvider.notifier).select(child);
                    if (context.mounted) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StudentDashboardScreen(),
                        ),
                      );
                      if (context.mounted) {
                        ref.read(activeChildProvider.notifier).deselect();
                      }
                    }
                  },
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF6B21A8),
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
                    title: Text(
                      child.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('${child.schoolType} • Klasse ${child.grade}'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${child.stars} Sterne',
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
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF6B21A8),
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

      // ── Bottom Bar ────────────────────────────────────────────────────────
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
                // ── Eltern-Dashboard Button ──────────────────────────────
                _BottomBarButton(
                  onTap: () => _openParentDashboard(context, ref),
                  badge: pendingRewards,
                  icon: Icons.family_restroom_rounded,
                  label: 'Eltern-Dashboard',
                  color: const Color(0xFF6B21A8),
                ),

                // ── Einstellungen Button ─────────────────────────────────
                _BottomBarButton(
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openParentDashboard(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

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
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
      );
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
