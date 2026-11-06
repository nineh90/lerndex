import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';

// ============================================================================
// REWARDS COUNT PROVIDER
//
// Zählt NUR einlösbare Eltern-Belohnungen (RewardType.parent + approved).
// Systembelohnungen (Achievements) werden hier bewusst nicht gezählt –
// sie haben keinen "Einlösen"-Flow und sollen den Badge nicht aufblasen.
// ============================================================================

/// Anzahl der einlösbaren Eltern-Belohnungen für das aktive Kind.
/// Wird als Badge in der Bottom-Navigation angezeigt.
final availableRewardsCountProvider = Provider<int>((ref) {
  // Nur die ID beobachten: XP-Änderungen am Kind sollen den Stream nicht
  // neu anmelden.
  final childId = ref.watch(activeChildProvider.select((c) => c?.id));
  final user = ref.watch(authStateChangesProvider).value;
  if (childId == null || user == null) return 0;
  final rewards = ref
      .watch(rewardsStreamProvider((userId: user.ownerUid, childId: childId)))
      .value;
  return rewards
          ?.where(
            (r) =>
                r.type == RewardType.parent &&
                r.status == RewardStatus.approved,
          )
          .length ??
      0;
});

/// Signal-Provider: wird auf true gesetzt wenn das Dashboard nach einem
/// Reward-Unlock zum Belohnungs-Tab wechseln soll.
/// Das Dashboard konsumiert ihn (liest + setzt ihn zurück auf false).
final navigateToRewardsTabProvider = StateProvider<bool>((ref) => false);
