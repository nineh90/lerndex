import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/auth_repository.dart';
import '../../data/profile_repository.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';

/// Anzahl eingelöster aber noch nicht ausgehändigter Belohnungen für ein Kind.
final _pendingRewardsForChildProvider = StreamProvider.family<int, String>((
  ref,
  childId,
) {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return Stream.value(0);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.ownerUid)
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
  final children = ref.watch(childrenListProvider).value ?? [];
  var total = 0;
  for (final child in children) {
    total += ref.watch(_pendingRewardsForChildProvider(child.id)).value ?? 0;
  }
  return total;
});
