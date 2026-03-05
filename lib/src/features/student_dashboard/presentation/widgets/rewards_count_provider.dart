import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';

// ============================================================================
// REWARDS COUNT PROVIDER
//
// Zählt NUR einlösbare Eltern-Belohnungen (RewardType.parent + approved).
// Systembelohnungen (Achievements) werden hier bewusst nicht gezählt –
// sie haben keinen "Einlösen"-Flow und sollen den Badge nicht aufblasen.
// ============================================================================

/// Anzahl der einlösbaren Eltern-Belohnungen für das aktive Kind.
/// Wird als Badge in der Bottom-Navigation angezeigt.
final availableRewardsCountProvider = StreamProvider<int>((ref) {
  final activeChild = ref.watch(activeChildProvider);
  final user = ref.watch(authStateChangesProvider).value;

  if (activeChild == null || user == null) return Stream.value(0);

  return ref
      .read(rewardServiceProvider)
      .getRewardsStream(userId: user.uid, childId: activeChild.id)
      .map(
        (rewards) => rewards
            .where(
              (r) =>
                  r.type == RewardType.parent &&
                  r.status == RewardStatus.approved,
            )
            .length,
      );
});
