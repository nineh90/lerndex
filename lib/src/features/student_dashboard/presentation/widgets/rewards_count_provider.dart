import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex1/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex1/src/features/auth/data/auth_repository.dart';
import 'package:lerndex1/src/features/rewards/data/reward_service.dart';
import 'package:lerndex1/src/features/rewards/domain/reward_enums.dart';

// ============================================================================
// REWARDS COUNT PROVIDER
//
// In eigener Datei damit sowohl student_dashboard_screen.dart als auch
// secondary_dashboard_screen.dart (und early_learner_dashboard_screen.dart)
// diesen Provider importieren können – ohne zirkuläre Abhängigkeiten.
// ============================================================================

/// Anzahl der einlösbaren (approved) Belohnungen für das aktive Kind.
final availableRewardsCountProvider = StreamProvider<int>((ref) {
  final activeChild = ref.watch(activeChildProvider);
  final user = ref.watch(authStateChangesProvider).value;

  if (activeChild == null || user == null) return Stream.value(0);

  return ref
      .read(rewardServiceProvider)
      .getRewardsStream(userId: user.uid, childId: activeChild.id)
      .map(
        (rewards) =>
            rewards.where((r) => r.status == RewardStatus.approved).length,
      );
});
