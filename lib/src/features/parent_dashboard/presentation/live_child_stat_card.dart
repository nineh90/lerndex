import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/generated_tasks/presentation/task_generator_screen.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/dashboard_mode_badge.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../rewards/presentation/manage_rewards_screen.dart';
import '../../rewards/data/xp_service.dart';
import '../../generated_tasks/presentation/task_approval_screen.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import 'child_statistics_screen.dart';
import 'tutor_history_screen.dart';
import '../../auth/data/profile_repository.dart';
import 'edit_child_screen.dart';
import 'widgets/claimed_rewards_banner.dart';
import 'widgets/stat_chip.dart';
import 'widgets/pulsing_dot.dart';

/// Provider für Live-Child-Daten (Stream für Echtzeit-Updates)
final liveChildProvider = StreamProvider.family<ChildModel?, String>((
  ref,
  childId,
) {
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

/// Provider für die Anzahl eingelöster (claimed) Belohnungen eines Kindes.
/// Eltern sehen damit sofort wenn ein Kind eine Belohnung beansprucht hat.
final claimedRewardsCountProvider = StreamProvider.family<int, String>((
  ref,
  childId,
) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(0);

  // Alle claimed Belohnungen holen und client-seitig filtern.
  // .where('parentSeen', isEqualTo: false) würde Dokumente ohne das Feld
  // (ältere Einlösungen) übersehen — daher manueller Filter.
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('children')
      .doc(childId)
      .collection('rewards')
      .where('status', isEqualTo: 'claimed')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.where((doc) {
          final data = doc.data();
          // parentSeen fehlt (altes Dokument) oder ist explizit false → zählen
          return data['parentSeen'] != true;
        }).length,
      );
});

/// Provider der prüft ob ein Kind gerade aktiv lernt.
///
/// "Live" = das Feld `lastActiveAt` in Firestore liegt weniger als 5 Minuten
/// zurück. Der [LearningTimeTracker] schreibt dieses Feld beim Start einer
/// Lernsession und dann alle 30 Sekunden als Heartbeat.
final childOnlineStatusProvider = StreamProvider.family<bool, String>((
  ref,
  childId,
) {
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

  const LiveChildStatCard({super.key, required this.childId});

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
                await ref.read(profileRepositoryProvider).deleteChild(child.id);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${child.name} wurde gelöscht'),
                      backgroundColor: Colors.deepPurple,
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
    final isOnline =
        ref.watch(childOnlineStatusProvider(childId)).value ?? false;

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

        // Berechne XP-Fortschritt (korrekt: XP im aktuellen Level / XP für dieses Level)
        final xpForThisLevel = XPService.calculateXPForLevel(child.level);
        final xpInLevel = XPService.calculateXPInCurrentLevel(
          child.xp,
          child.level,
        );
        final isMaxLevel = child.level >= XPService.maxLevel;
        final progress = isMaxLevel
            ? 1.0
            : (xpInLevel / xpForThisLevel).clamp(0.0, 1.0);
        final rank = XPService.getRankForLevel(child.level);

        // pendingCount für das Menü-Label
        final user = ref.watch(authStateChangesProvider).value;
        final pendingCountAsync = user != null
            ? ref.watch(pendingTaskCountProvider(user.uid))
            : null;
        final pendingCount = pendingCountAsync?.value ?? 0;

        // claimedCount: eingelöste Belohnungen die Eltern noch nicht gesehen haben
        final claimedCount =
            ref.watch(claimedRewardsCountProvider(childId)).value ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: claimedCount > 0 ? 5 : 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: claimedCount > 0
                ? BorderSide(color: Colors.deepPurple.shade300, width: 1.5)
                : BorderSide.none,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Benachrichtigungs-Banner (nur wenn eingelöste Belohnungen) ──
              if (claimedCount > 0)
                ClaimedRewardsBanner(
                  count: claimedCount,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageRewardsScreen(child: child),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header: Avatar + Name + LIVE-Badge (nur wenn aktiv) + Menü ──
                    Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: Colors.deepPurple.shade100,
                              backgroundImage: child.selectedAvatar != null
                                  ? AssetImage(
                                      'assets/images/${child.selectedAvatar}.png',
                                    )
                                  : null,
                              child: child.selectedAvatar == null
                                  ? Text(
                                      child.name[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepPurple,
                                      ),
                                    )
                                  : null,
                            ),
                            if (claimedCount > 0)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.shade600,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      claimedCount > 9 ? '9+' : '$claimedCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
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
                              const SizedBox(height: 4),
                              DashboardModeBadge(grade: child.grade),
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
                                const PulsingDot(),
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
                                    builder: (_) =>
                                        EditChildScreen(child: child),
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
                                    builder: (_) =>
                                        ManageRewardsScreen(child: child),
                                  ),
                                );
                                break;
                              case 'ai_tasks':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TaskGeneratorScreen(child: child),
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
                                    builder: (_) =>
                                        TutorHistoryScreen(child: child),
                                  ),
                                );
                                break;
                              case 'statistics':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ChildStatisticsScreen(child: child),
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
                                  Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Löschen',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),

                            // ── Trennlinie ─────────────────────────────────────
                            const PopupMenuDivider(),

                            // ── Belohnungen verwalten ──────────────────────────
                            PopupMenuItem(
                              value: 'rewards',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.card_giftcard,
                                    size: 18,
                                    color: claimedCount > 0
                                        ? Colors.deepPurple
                                        : Colors.deepPurple,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    claimedCount > 0
                                        ? 'Belohnungen verwalten ($claimedCount eingelöst!)'
                                        : 'Belohnungen verwalten',
                                    style: TextStyle(
                                      color: claimedCount > 0
                                          ? Colors.deepPurple
                                          : null,
                                      fontWeight: claimedCount > 0
                                          ? FontWeight.bold
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ── KI-Aufgaben generieren ─────────────────────────
                            const PopupMenuItem(
                              value: 'ai_tasks',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 18,
                                    color: Colors.deepPurple,
                                  ),
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
                                    color: pendingCount > 0
                                        ? Colors.deepPurple
                                        : Colors.green,
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
                                  Icon(
                                    Icons.chat,
                                    size: 18,
                                    color: Colors.deepPurple,
                                  ),
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
                                  Icon(
                                    Icons.bar_chart,
                                    size: 18,
                                    color: Colors.indigo,
                                  ),
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

                    // ── Level + Rang + XP-Balken ──────────────────────────────
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: rank.color,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Lvl ${child.level}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${rank.emoji} ${rank.title}',
                              style: TextStyle(
                                fontSize: 10,
                                color: rank.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey.shade200,
                                  color: rank.color,
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              isMaxLevel
                                  ? Text(
                                      '🏆 Max Level erreicht! (${child.xp} XP gesamt)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: rank.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : Text(
                                      '$xpInLevel / $xpForThisLevel XP · noch ${xpForThisLevel - xpInLevel} bis Lvl ${child.level + 1}',
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
                        StatChip(
                          icon: Icons.star,
                          color: Colors.deepPurple,
                          label: '${child.stars} Sterne',
                        ),
                        const SizedBox(width: 8),
                        StatChip(
                          icon: Icons.local_fire_department,
                          color: Colors.deepPurple.shade300,
                          label: '${child.streak ?? 0} Tage',
                        ),
                        const SizedBox(width: 8),
                        StatChip(
                          icon: Icons.timer,
                          color: Colors.blue,
                          label: child.formattedLearningTime,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
