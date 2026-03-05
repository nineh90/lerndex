import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/auth_repository.dart';
import '../../data/profile_repository.dart';

/// Anzahl eingelöster aber noch nicht ausgehändigter Belohnungen für ein Kind.
final _pendingRewardsForChildProvider = StreamProvider.family<int, String>((
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
        (snap) =>
            snap.docs.where((doc) => doc.data()['parentSeen'] != true).length,
      );
});

/// Gesamtzahl über alle Kinder – summiert die Einzel-Provider.
/// Reaktiv: aktualisiert sich automatisch wenn sich ein Kind-Count ändert.
final totalPendingRewardsProvider = Provider<int>((ref) {
  final children = ref.watch(childrenListProvider).valueOrNull ?? [];
  var total = 0;
  for (final child in children) {
    total +=
        ref.watch(_pendingRewardsForChildProvider(child.id)).valueOrNull ?? 0;
  }
  return total;
});

// ============================================================================
// PARENT DASHBOARD BUTTON MIT BADGE
// ============================================================================

class ParentDashboardButton extends ConsumerWidget {
  final VoidCallback onTap;
  const ParentDashboardButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(totalPendingRewardsProvider);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Eltern-Dashboard',
            onPressed: onTap,
          ),
          if (count > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 164, 32, 32),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color.fromARGB(255, 106, 15, 15),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
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
    );
  }
}
