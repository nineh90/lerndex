import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/auth_repository.dart';

/// Gesamtzahl eingelöster aber noch nicht ausgehändigter Belohnungen aller Kinder.
/// Nutzt collectionGroup damit Änderungen in rewards-Subcollections live ankommen.
final totalPendingRewardsProvider = StreamProvider<int>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collectionGroup('rewards')
      .where('status', isEqualTo: 'claimed')
      .snapshots()
      .map((snap) {
        final uid = user.uid;
        final filtered = snap.docs.where((doc) {
          final path = doc.reference.path;
          if (!path.startsWith('users/$uid/')) return false;
          return doc.data()['parentSeen'] != true;
        });
        return filtered.length;
      });
});

// ============================================================================
// PARENT DASHBOARD BUTTON MIT BADGE
// ============================================================================

class ParentDashboardButton extends ConsumerWidget {
  final VoidCallback onTap;
  const ParentDashboardButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(totalPendingRewardsProvider).valueOrNull ?? 0;

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
