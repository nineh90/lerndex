import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../rewards/presentation/manage_rewards_screen.dart';
import '../../rewards/data/xp_service.dart';
import '../../generated_tasks/presentation/improved_ai_task_generator_screen.dart';
import '../../generated_tasks/presentation/task_approval_screen.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import 'child_statistics_screen.dart';
import 'tutor_history_screen.dart';
import '../../auth/data/profile_repository.dart';
import 'edit_child_screen.dart';

/// Provider für Live-Child-Daten (Stream für Echtzeit-Updates)
final liveChildProvider = StreamProvider.family<ChildModel?, String>((ref, childId) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('children')
      .doc(childId)
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists) return null;
    return ChildModel.fromFirestore(snapshot.data()!, snapshot.id);
  });
});

/// Provider der prüft ob ein Kind gerade aktiv lernt.
///
/// "Live" = das Feld `lastActiveAt` in Firestore liegt weniger als 5 Minuten
/// zurück. Der [LearningTimeTracker] schreibt dieses Feld beim Start einer
/// Lernsession und dann alle 30 Sekunden als Heartbeat.
final childOnlineStatusProvider = StreamProvider.family<bool, String>((ref, childId) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(false);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('children')
      .doc(childId)
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists) return false;

    final data = snapshot.data();
    if (data == null) return false;

    final lastActiveAt = (data['lastActiveAt'] as Timestamp?)?.toDate();
    if (lastActiveAt == null) return false;

    // Live = letzter Heartbeat vor weniger als 5 Minuten
    final diff = DateTime.now().difference(lastActiveAt);
    return diff.inMinutes < 5;
  });
});

// =============================================================================
// WIDGET
// =============================================================================

/// Statistik-Karte mit LIVE-Updates und echtem Online-Status
class LiveChildStatCard extends ConsumerWidget {
  final String childId;

  const LiveChildStatCard({
    super.key,
    required this.childId,
  });

  // =========================================================================
  // DELETE DIALOG
  // =========================================================================

  void _confirmDelete(BuildContext context, WidgetRef ref, ChildModel child) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Kind löschen'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  const TextSpan(text: 'Möchtest du '),
                  TextSpan(
                    text: child.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' wirklich löschen? '),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('Alle Daten werden dauerhaft entfernt.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(profileRepositoryProvider)
                    .deleteChild(child.id);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${child.name} wurde gelöscht'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Fehler beim Löschen: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ja, löschen'),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childAsync = ref.watch(liveChildProvider(childId));
    final isOnline = ref.watch(childOnlineStatusProvider(childId)).value ?? false;

    return childAsync.when(
      data: (child) {
        if (child == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kind nicht gefunden'),
            ),
          );
        }

        // Berechne XP-Fortschritt
        final xpForNextLevel = XPService.calculateXPForLevel(child.level);
        int currentLevelXP = child.xp;

        for (int i = 1; i < child.level; i++) {
          currentLevelXP -= XPService.calculateXPForLevel(i);
        }

        final progress = currentLevelXP / xpForNextLevel;

        // pendingCount für das Menü-Label
        final user = ref.watch(authStateChangesProvider).value;
        final pendingCountAsync = user != null
            ? ref.watch(pendingTaskCountProvider(user.uid))
            : null;
        final pendingCount = pendingCountAsync?.value ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header: Avatar + Name + LIVE-Badge (nur wenn aktiv) + Menü ──
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.deepPurple.shade100,
                      child: Text(
                        child.name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            child.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${child.schoolType} • Klasse ${child.grade}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),

                    // LIVE-Badge – NUR anzeigen wenn Kind wirklich aktiv ist
                    if (isOnline) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PulsingDot(),
                            const SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],

                    // ── Drei-Punkte-Menü (inkl. aller Aktionen) ────────────
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditChildScreen(child: child),
                              ),
                            );
                            break;
                          case 'delete':
                            _confirmDelete(context, ref, child);
                            break;
                          case 'rewards':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ManageRewardsScreen(child: child),
                              ),
                            );
                            break;
                          case 'ai_tasks':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImprovedAITaskGeneratorScreen(child: child),
                              ),
                            );
                            break;
                          case 'approve_tasks':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TaskApprovalScreen(),
                              ),
                            );
                            break;
                          case 'tutor':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TutorHistoryScreen(child: child),
                              ),
                            );
                            break;
                          case 'statistics':
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChildStatisticsScreen(child: child),
                              ),
                            );
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        // ── Bearbeiten & Löschen ──────────────────────────
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Bearbeiten'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Löschen', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),

                        // ── Trennlinie ─────────────────────────────────────
                        const PopupMenuDivider(),

                        // ── Belohnungen verwalten ──────────────────────────
                        const PopupMenuItem(
                          value: 'rewards',
                          child: Row(
                            children: [
                              Icon(Icons.card_giftcard, size: 18, color: Colors.amber),
                              SizedBox(width: 8),
                              Text('Belohnungen verwalten'),
                            ],
                          ),
                        ),

                        // ── KI-Aufgaben generieren ─────────────────────────
                        const PopupMenuItem(
                          value: 'ai_tasks',
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome, size: 18, color: Colors.deepPurple),
                              SizedBox(width: 8),
                              Text('KI-Aufgaben generieren'),
                            ],
                          ),
                        ),

                        // ── Aufgaben freigeben ─────────────────────────────
                        PopupMenuItem(
                          value: 'approve_tasks',
                          child: Row(
                            children: [
                              Icon(
                                Icons.task_alt,
                                size: 18,
                                color: pendingCount > 0 ? Colors.orange : Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                pendingCount > 0
                                    ? 'Aufgaben freigeben ($pendingCount)'
                                    : 'Aufgaben freigeben',
                              ),
                            ],
                          ),
                        ),

                        // ── Tutor-Gespräche ────────────────────────────────
                        const PopupMenuItem(
                          value: 'tutor',
                          child: Row(
                            children: [
                              Icon(Icons.chat, size: 18, color: Colors.deepPurple),
                              SizedBox(width: 8),
                              Text('Tutor-Gespräche'),
                            ],
                          ),
                        ),

                        // ── Statistiken ────────────────────────────────────
                        const PopupMenuItem(
                          value: 'statistics',
                          child: Row(
                            children: [
                              Icon(Icons.bar_chart, size: 18, color: Colors.indigo),
                              SizedBox(width: 8),
                              Text('Statistiken'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Level + XP-Balken ──────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Level ${child.level}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              backgroundColor: Colors.grey.shade200,
                              color: Colors.deepPurple,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${child.xp} / $xpForNextLevel XP',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Statistik-Grid ─────────────────────────────────────────
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.star,
                      color: Colors.amber,
                      label: '${child.stars} Sterne',
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.local_fire_department,
                      color: Colors.orange,
                      label: '${child.streak ?? 0} Tage',
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.timer,
                      color: Colors.blue,
                      label: child.formattedLearningTime,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Fehler: $e'),
        ),
      ),
    );
  }
}

// =============================================================================
// HELPER WIDGETS
// =============================================================================

/// Kleines Statistik-Chip
class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _StatChip({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animierter pulsierender Punkt für den Live-Indikator.
/// Blinkt sanft um anzuzeigen dass das Kind gerade aktiv ist.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}