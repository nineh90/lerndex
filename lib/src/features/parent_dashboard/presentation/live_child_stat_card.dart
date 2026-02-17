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

/// VERBESSERTE Statistik-Karte mit LIVE-Updates
class LiveChildStatCard extends ConsumerWidget {
  final String childId;

  const LiveChildStatCard({
    super.key,
    required this.childId,
  });

  // =========================================================================
  // DELETE DIALOG – korrekt in LiveChildStatCard
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
                  const TextSpan(text: ' wirklich löschen?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Alle Fortschritte, XP, Sterne und Tutor-Gespräche werden unwiderruflich gelöscht.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
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
                await ref.read(profileRepositoryProvider).deleteChild(child.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${child.name} wurde gelöscht.'),
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

                // ── Header: Avatar + Name + LIVE-Badge + Menü ──────────────
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
                    // LIVE-Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
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
                    // Bearbeiten / Löschen Menü
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      tooltip: 'Optionen',
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await Navigator.push(
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
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Colors.deepPurple, size: 20),
                              SizedBox(width: 10),
                              Text('Bearbeiten'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red, size: 20),
                              SizedBox(width: 10),
                              Text('Löschen',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Statistiken ────────────────────────────────────────────
                Row(
                  children: [
                    _StatBox(
                      icon: Icons.emoji_events,
                      label: 'Level',
                      value: '${child.level}',
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    _StatBox(
                      icon: Icons.stars,
                      label: 'Sterne',
                      value: '${child.stars}',
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 12),
                    _StatBox(
                      icon: Icons.auto_graph,
                      label: 'XP',
                      value: '${child.xp}',
                      color: Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── XP-Fortschritt ─────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Fortschritt zum nächsten Level',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeInOut,
                      tween: Tween<double>(
                          begin: 0, end: progress.clamp(0.0, 1.0)),
                      builder: (context, value, child) {
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.deepPurple),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$currentLevelXP / $xpForNextLevel XP',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Aktionen: Belohnungen + KI-Aufgaben ───────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageRewardsScreen(child: child),
                            ),
                          );
                        },
                        icon: const Icon(Icons.card_giftcard, size: 18),
                        label: const Text('Belohnungen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
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
                        label: const Text('KI-Aufgaben'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple,
                          side: const BorderSide(color: Colors.deepPurple),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ── Aufgaben freigeben ─────────────────────────────────────
                Consumer(
                  builder: (context, ref, _) {
                    final authRepo = ref.watch(authRepositoryProvider);
                    final userId = authRepo.currentUser?.uid ?? '';
                    final pendingCountAsync =
                    ref.watch(pendingTaskCountProvider(userId));

                    return pendingCountAsync.when(
                      data: (pendingCount) {
                        return SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TaskApprovalScreen(),
                                ),
                              );
                            },
                            icon: pendingCount > 0
                                ? Badge(
                              label: Text('$pendingCount'),
                              child:
                              const Icon(Icons.check_circle, size: 18),
                            )
                                : const Icon(Icons.check_circle, size: 18),
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
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                ),
                const SizedBox(height: 8),

                // ── Tutor-Gespräche ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TutorHistoryScreen(child: child),
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

                // ── Statistiken ────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
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
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        margin: EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stack) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Fehler: $error'),
        ),
      ),
    );
  }
}

// =============================================================================
// HILFWIDGET: Kleine Statistik-Box
// =============================================================================

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}