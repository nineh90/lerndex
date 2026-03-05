import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../domain/reward_model.dart';
import '../domain/reward_enums.dart';
import 'xp_service.dart';
import 'validation_result.dart';

/// Service für Belohnungs-Verwaltung mit Auto-Triggern
class RewardService {
  final FirebaseFirestore _firestore;

  RewardService(this._firestore);

  /// Erstellt eine System-Belohnung (automatisch approved)
  Future<RewardModel> createSystemReward({
    required String userId,
    required String childId,
    required String title,
    required String description,
    required String reward,
    required RewardTrigger trigger,
    int? requiredLevel,
    int? bonusXP,
    String? avatarUnlockId,
    String? badgeId,
  }) async {
    try {
      final rewardData = RewardModel(
        id: '',
        childId: childId,
        title: title,
        description: description,
        type: RewardType.system,
        trigger: trigger,
        requiredLevel: requiredLevel,
        bonusXP: bonusXP,
        avatarUnlockId: avatarUnlockId,
        status: RewardStatus.approved,
        reward: reward,
        createdAt: DateTime.now(),
        approvedAt: DateTime.now(),
        createdBy: 'system',
      );

      final docRef = await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('rewards')
          .add(rewardData.toFirestore());

      print('✅ System-Belohnung erstellt: $title');
      return rewardData.copyWith(id: docRef.id);
    } catch (e) {
      print('❌ Fehler beim Erstellen der System-Belohnung: $e');
      rethrow;
    }
  }

  /// Prüft alle pending Belohnungen und aktiviert getriggerte
  Future<List<RewardModel>> checkAndApproveRewards({
    required String userId,
    required ChildModel child,
    bool isPerfectQuiz = false,
  }) async {
    try {
      print('🔍 Prüfe Belohnungen für ${child.name}...');

      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(child.id)
          .collection('rewards')
          .where('status', isEqualTo: 'pending')
          .get();

      final List<RewardModel> approvedRewards = [];

      for (var doc in snapshot.docs) {
        final reward = RewardModel.fromFirestore(doc.data(), doc.id);

        final isTriggered = reward.isTriggeredBy(
          currentLevel: child.level,
          currentXP: child.xp,
          currentStars: child.stars,
          currentStreak: child.streak ?? 0,
          currentQuizCount: child.totalQuizzes ?? 0,
          isPerfectQuiz: isPerfectQuiz,
        );

        if (isTriggered) {
          await doc.reference.update({
            'status': 'approved',
            'approvedAt': FieldValue.serverTimestamp(),
          });

          print('✅ Belohnung freigeschaltet: ${reward.title}');

          // ⚡ Bonus-XP automatisch vergeben
          if (reward.bonusXP != null && reward.bonusXP! > 0) {
            try {
              final xpService = XPService(_firestore);
              await xpService.addXP(
                userId: userId,
                childId: child.id,
                xpToAdd: reward.bonusXP!,
              );
              print('⚡ +${reward.bonusXP} Bonus-XP vergeben');
            } catch (e) {
              print('❌ Fehler beim Vergeben von Bonus-XP: $e');
            }
          }

          // 🎭 Avatar automatisch freischalten
          if (reward.avatarUnlockId != null) {
            try {
              await _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('children')
                  .doc(child.id)
                  .update({
                    'unlockedAvatars': FieldValue.arrayUnion([
                      reward.avatarUnlockId!,
                    ]),
                  });
              print('🎭 Avatar freigeschaltet: ${reward.avatarUnlockId}');
            } catch (e) {
              print('❌ Fehler beim Freischalten des Avatars: $e');
            }
          }

          approvedRewards.add(
            reward.copyWith(
              status: RewardStatus.approved,
              approvedAt: DateTime.now(),
            ),
          );
        }
      }

      return approvedRewards;
    } catch (e) {
      print('❌ Fehler beim Prüfen der Belohnungen: $e');
      return [];
    }
  }

  /// Erstellt eine dynamische Level-Up Systembelohnung (für Level die nicht
  /// im SystemRewardsInitializer vordefiniert sind, z.B. Level 4, 6, 8...).
  /// Für vordefinierte Level-Achievements (2, 3, 5, 7, 10, 15, 20) greift
  /// der SystemRewardsInitializer – diese Methode greift nur als Fallback.
  Future<RewardModel?> createLevelUpReward({
    required String userId,
    required String childId,
    required int level,
  }) async {
    try {
      final existing = await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('rewards')
          .where('type', isEqualTo: 'system')
          .where('trigger', isEqualTo: 'level')
          .where('requiredLevel', isEqualTo: level)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        print('ℹ️ Level-Up Belohnung existiert bereits');
        return null;
      }

      final xpBonus = _getLevelUpBonusXP(level);

      return await createSystemReward(
        userId: userId,
        childId: childId,
        title: '🎉 Level $level erreicht!',
        description: 'Du hast Level $level geschafft – weiter so!',
        reward: '+$xpBonus Bonus-XP',
        trigger: RewardTrigger.level,
        requiredLevel: level,
        bonusXP: xpBonus,
        badgeId: 'badge-level-$level',
      );
    } catch (e) {
      print('❌ Fehler beim Erstellen der Level-Up Belohnung: $e');
      return null;
    }
  }

  /// Erstellt eine Perfect-Quiz Systembelohnung (rein digital)
  Future<RewardModel?> createPerfectQuizReward({
    required String userId,
    required String childId,
  }) async {
    try {
      return await createSystemReward(
        userId: userId,
        childId: childId,
        title: '⭐ Perfektes Quiz!',
        description: 'Alle Fragen auf Anhieb richtig beantwortet!',
        reward: '+40 Bonus-XP & Badge „Perfektionist"',
        trigger: RewardTrigger.perfectQuiz,
        bonusXP: 40,
        badgeId: 'badge-perfect-quiz',
      );
    } catch (e) {
      print('❌ Fehler beim Erstellen der Perfect-Quiz Belohnung: $e');
      return null;
    }
  }

  /// Löst eine Eltern-Belohnung ein (setzt parentSeen = false → Eltern werden informiert)
  Future<void> claimReward({
    required String userId,
    required String childId,
    required String rewardId,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('rewards')
          .doc(rewardId)
          .update({
            'status': 'claimed',
            'claimedAt': FieldValue.serverTimestamp(),
            'parentSeen': false,
          });

      print('✅ Belohnung eingelöst!');
    } catch (e) {
      print('❌ Fehler beim Einlösen der Belohnung: $e');
      rethrow;
    }
  }

  /// Markiert alle eingelösten Belohnungen eines Kindes als von Eltern gesehen
  Future<void> markClaimedRewardsAsSeen({
    required String userId,
    required String childId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('rewards')
          .where('status', isEqualTo: 'claimed')
          .get();

      final unseen = snapshot.docs
          .where((doc) => doc.data()['parentSeen'] != true)
          .toList();

      if (unseen.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in unseen) {
        batch.update(doc.reference, {'parentSeen': true});
      }
      await batch.commit();
      print('✅ ${unseen.length} Belohnungen als gesehen markiert');
    } catch (e) {
      print('❌ Fehler beim Markieren als gesehen: $e');
    }
  }

  /// Stream aller Belohnungen eines Kindes
  Stream<List<RewardModel>> getRewardsStream({
    required String userId,
    required String childId,
    RewardStatus? status,
  }) {
    var query = _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .orderBy('createdAt', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status.toFirestore());
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => RewardModel.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  /// Validiert ob eine Eltern-Belohnung erstellt werden kann
  ValidationResult validateParentReward({
    required ChildModel child,
    required RewardTrigger trigger,
    int? requiredLevel,
    int? requiredXP,
    int? requiredStars,
  }) {
    switch (trigger) {
      case RewardTrigger.level:
        if (requiredLevel == null) {
          return ValidationResult(false, 'Bitte Level angeben');
        }
        if (requiredLevel <= child.level) {
          return ValidationResult(
            false,
            '${child.name} ist bereits auf Level ${child.level}. Wähle ein höheres Level!',
          );
        }
        return ValidationResult(true, '');

      case RewardTrigger.xp:
        if (requiredXP == null) {
          return ValidationResult(false, 'Bitte XP angeben');
        }
        if (requiredXP <= child.xp) {
          return ValidationResult(
            false,
            '${child.name} hat bereits ${child.xp} XP. Wähle mehr XP!',
          );
        }
        return ValidationResult(true, '');

      case RewardTrigger.stars:
        if (requiredStars == null) {
          return ValidationResult(false, 'Bitte Sterne angeben');
        }
        if (requiredStars <= child.stars) {
          return ValidationResult(
            false,
            '${child.name} hat bereits ${child.stars} Sterne. Wähle mehr Sterne!',
          );
        }
        return ValidationResult(true, '');

      default:
        return ValidationResult(true, '');
    }
  }

  /// Bonus-XP für dynamische Level-Up Belohnungen (Fallback für nicht
  /// vordefinierte Level)
  int _getLevelUpBonusXP(int level) {
    if (level <= 3) return 25;
    if (level <= 5) return 50;
    if (level <= 10) return 100;
    if (level <= 15) return 200;
    return 300;
  }
}

/// Provider für Reward Service
final rewardServiceProvider = Provider<RewardService>((ref) {
  return RewardService(FirebaseFirestore.instance);
});
