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

// =============================================================================
// PROVIDER
// =============================================================================

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
                  const TextSpan(text: ' wirklich löschen? Alle Daten werden dauerhaft entfernt.'),
                ],
              ),
            ),
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

                    // Menü
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditChildScreen(child: child),
                            ),
                          );
                        } else if (value == 'delete') {
                          _confirmDelete(context, ref, child);
                        }
                      },
                      itemBuilder: (context) => [
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

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── Aktions-Buttons ────────────────────────────────────────
                Consumer(
                  builder: (context, ref, _) {
                    final user = ref.watch(authStateChangesProvider).value;
                    if (user == null) return const SizedBox.shrink();

                    final pendingCountAsync = ref.watch(
                      pendingTaskCountProvider(user.uid),
                    );

                    final pendingCount = pendingCountAsync.value ?? 0;

                    return Column(
                      children: [
                        // ── Belohnungen verwalten ──────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ManageRewardsScreen(child: child),
                                ),
                              );
                            },
                            icon: const Icon(Icons.card_giftcard, size: 18),
                            label: const Text('Belohnungen verwalten'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber,
                              side: const BorderSide(color: Colors.amber),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ── KI-Aufgaben generieren ─────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ImprovedAITaskGeneratorScreen(child: child),
                                ),
                              );
                            },
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('KI-Aufgaben generieren'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ── Aufgaben freigeben ─────────────────────────────
                        pendingCountAsync.when(
                          data: (_) => SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                    const TaskApprovalScreen(),
                                  ),
                                );
                              },
                              icon: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.task_alt, size: 18),
                                  if (pendingCount > 0)
                                    Positioned(
                                      right: -6,
                                      top: -4,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '$pendingCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              label: Text(
                                pendingCount > 0
                                    ? 'Aufgaben freigeben ($pendingCount)'
                                    : 'Aufgaben freigeben',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: pendingCount > 0
                                    ? Colors.orange
                                    : Colors.green,
                                side: BorderSide(
                                  color: pendingCount > 0
                                      ? Colors.orange
                                      : Colors.green,
                                ),
                              ),
                            ),
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 8),

                        // ── Tutor-Gespräche ────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TutorHistoryScreen(child: child),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat, size: 18),
                            label: const Text('Tutor-Gespräche'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.deepPurple,
                              side: const BorderSide(color: Colors.deepPurple),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ── Statistiken ────────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ChildStatisticsScreen(child: child),
                                ),
                              );
                            },
                            icon: const Icon(Icons.bar_chart, size: 18),
                            label: const Text('Statistiken'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.indigo,
                              side: const BorderSide(color: Colors.indigo),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}