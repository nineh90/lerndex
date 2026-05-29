import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/generated_tasks/presentation/task_generator_screen.dart';
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
import '../../subscription/presentation/paywall_screen.dart';

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
final claimedRewardsCountProvider = StreamProvider.family<int, String>((
  ref,
  childId,
) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(0);

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
          return data['parentSeen'] != true;
        }).length,
      );
});

/// Provider der prüft ob ein Kind gerade aktiv lernt.
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
        return DateTime.now().difference(lastActiveAt).inMinutes < 5;
      });
});

// =============================================================================
// WIDGET
// =============================================================================

class LiveChildStatCard extends ConsumerWidget {
  final String childId;

  const LiveChildStatCard({super.key, required this.childId});

  // ── Delete Dialog ───────────────────────────────────────────────────────────

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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childAsync = ref.watch(liveChildProvider(childId));
    final isOnline =
        ref.watch(childOnlineStatusProvider(childId)).value ?? false;

    return childAsync.when(
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
      data: (child) {
        if (child == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kind nicht gefunden'),
            ),
          );
        }

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

        final user = ref.watch(authStateChangesProvider).value;
        final pendingCount = user != null
            ? ref
                      .watch(
                        pendingTaskCountForChildProvider((
                          userId: user.uid,
                          childId: childId,
                        )),
                      )
                      .value ??
                  0
            : 0;
        final claimedCount =
            ref.watch(claimedRewardsCountProvider(childId)).value ?? 0;

        // ── Karte ────────────────────────────────────────────────────────────
        final card = Card(
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
                    // ── Header ───────────────────────────────────────────────
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
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepPurple.shade700,
                                      ),
                                    )
                                  : null,
                            ),
                            if (isOnline)
                              const Positioned(
                                right: -2,
                                bottom: -2,
                                child: PulsingDot(),
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
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${child.schoolType} • Klasse ${child.grade}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Popup-Menü ────────────────────────────────────────
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
                              case 'rewards':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ManageRewardsScreen(child: child),
                                  ),
                                );
                              case 'ai_tasks':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TaskGeneratorScreen(child: child),
                                  ),
                                );
                              case 'approve_tasks':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TaskApprovalScreen(childId: childId),
                                  ),
                                );
                              case 'tutor':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TutorHistoryScreen(child: child),
                                  ),
                                );
                              case 'statistics':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ChildStatisticsScreen(child: child),
                                  ),
                                );
                              case 'delete':
                                _confirmDelete(context, ref, child);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Colors.deepPurple,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Bearbeiten'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'rewards',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.card_giftcard,
                                    size: 18,
                                    color: Colors.deepPurple,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Belohnungen'),
                                ],
                              ),
                            ),
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
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_forever,
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

                    // ── Statistik-Chips ───────────────────────────────────────
                    Row(
                      children: [
                        StatChip(
                          icon: Icons.bolt,
                          color: Colors.orange,
                          label: '${child.xp} XP',
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

        // ── Stack: ausgegraut + Overlay mit echten Farben ─────────────────────
        return Stack(
          children: [
            // Karte grau + gesperrt wenn inaktiv
            ColorFiltered(
              colorFilter: child.isActive
                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                  : const ColorFilter.matrix([
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
              child: IgnorePointer(ignoring: !child.isActive, child: card),
            ),

            // Overlay AUSSERHALB ColorFiltered → Buttons behalten echte Farben
            if (!child.isActive)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black.withValues(alpha: 0.04),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Pausiert-Label
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, color: Colors.white, size: 13),
                            SizedBox(width: 6),
                            Text(
                              'Pausiert',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Löschen + Upgraden
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () =>
                                _confirmDelete(context, ref, child),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Löschen'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(fontSize: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PaywallScreen(canDismiss: true),
                              ),
                            ),
                            icon: const Icon(Icons.upgrade, size: 16),
                            label: const Text('Upgraden'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6B21A8),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(fontSize: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
