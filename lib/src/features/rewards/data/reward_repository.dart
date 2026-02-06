import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/reward_model.dart';
import '../../auth/domain/child_model.dart';

/// Temporärer Stub für Reward Repository
class RewardRepository {
  final FirebaseFirestore _firestore;

  RewardRepository(this._firestore);

  /// Stub: Gibt leere Liste zurück
  Stream<List<RewardModel>> watchRewardsForChild(String childId) {
    return Stream.value([]);
  }

  /// Stub: Macht nichts
  Future<List<RewardModel>> checkAndUnlockRewards(ChildModel child) async {
    return [];
  }
}

/// Provider
final rewardRepositoryProvider = Provider<RewardRepository>((ref) {
  return RewardRepository(FirebaseFirestore.instance);
});

/// Stub Provider
final childRewardsProvider = StreamProvider.family<List<RewardModel>, String>((ref, childId) {
  return Stream.value([]);
});