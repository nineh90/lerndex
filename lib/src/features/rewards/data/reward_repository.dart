import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/reward_model.dart';
import '../../auth/domain/child_model.dart';

/// Repository für Belohnungs-Verwaltung
class RewardRepository {
  RewardRepository(this._firestore, this._auth);
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? '';

  /// Stream aller Belohnungen für ein Kind
  Stream<List<Reward>> watchRewardsForChild(String childId) {
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Reward.fromMap(doc.data(), doc.id))
        .toList());
  }

  /// Erstellt eine neue Belohnung
  Future<void> addReward({
    required String childId,
    required String title,
    required String description,
    required String icon,
    required String trigger,
    required int triggerValue,
  }) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .add({
      'childId': childId,
      'title': title,
      'description': description,
      'icon': icon,
      'trigger': trigger,
      'triggerValue': triggerValue,
      'isUnlocked': false,
      'isRedeemed': false,
      'unlockedAt': null,
      'redeemedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Schaltet eine Belohnung frei (wird vom System aufgerufen)
  Future<void> unlockReward(String childId, String rewardId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .doc(rewardId)
        .update({
      'isUnlocked': true,
      'unlockedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Markiert eine Belohnung als eingelöst (vom Kind verwendet)
  Future<void> redeemReward(String childId, String rewardId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .doc(rewardId)
        .update({
      'isRedeemed': true,
      'redeemedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Löscht eine Belohnung
  Future<void> deleteReward(String childId, String rewardId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .doc(rewardId)
        .delete();
  }

  /// Aktualisiert eine Belohnung
  Future<void> updateReward(
      String childId,
      String rewardId, {
        String? title,
        String? description,
        String? icon,
        String? trigger,
        int? triggerValue,
      }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;
    if (icon != null) updates['icon'] = icon;
    if (trigger != null) updates['trigger'] = trigger;
    if (triggerValue != null) updates['triggerValue'] = triggerValue;

    if (updates.isNotEmpty) {
      await _firestore
          .collection('users')
          .doc(_uid)
          .collection('children')
          .doc(childId)
          .collection('rewards')
          .doc(rewardId)
          .update(updates);
    }
  }

  /// Prüft ob Belohnungen freigeschaltet werden müssen
  /// Wird nach Quiz, Level-Up, etc. aufgerufen
  Future<List<Reward>> checkAndUnlockRewards(ChildModel child) async {
    final newlyUnlocked = <Reward>[];

    // Lade alle Belohnungen für dieses Kind
    final rewardsSnapshot = await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(child.id)
        .collection('rewards')
        .where('isUnlocked', isEqualTo: false) // Nur noch gesperrte
        .get();

    for (var doc in rewardsSnapshot.docs) {
      final reward = Reward.fromMap(doc.data(), doc.id);

      // Prüfe ob Bedingung erfüllt ist
      bool shouldUnlock = false;

      switch (reward.trigger) {
        case RewardTrigger.level:
          shouldUnlock = child.level >= reward.triggerValue;
          break;
        case RewardTrigger.stars:
          shouldUnlock = child.stars >= reward.triggerValue;
          break;
        case RewardTrigger.learningTime:
          final minutes = child.totalLearningSeconds ~/ 60;
          shouldUnlock = minutes >= reward.triggerValue;
          break;
      // Weitere Trigger können hier ergänzt werden
      }

      if (shouldUnlock) {
        await unlockReward(child.id, reward.id);
        newlyUnlocked.add(reward);
      }
    }

    return newlyUnlocked;
  }
}

/// Provider für RewardRepository
final rewardRepositoryProvider = Provider<RewardRepository>((ref) {
  return RewardRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

/// Provider für Belohnungen eines Kindes
final childRewardsProvider = StreamProvider.family<List<Reward>, String>((ref, childId) {
  return ref.watch(rewardRepositoryProvider).watchRewardsForChild(childId);
});