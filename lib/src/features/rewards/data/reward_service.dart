import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../domain/reward_model.dart';
import '../domain/reward_enums.dart';

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
  }) async {
    try {
      final rewardData = RewardModel(
        id: '', // Wird von Firestore gesetzt
        childId: childId,
        title: title,
        description: description,
        type: RewardType.system,
        trigger: trigger,
        requiredLevel: requiredLevel,
        status: RewardStatus.approved,  // System-Belohnungen sofort approved!
        reward: reward,
        createdAt: DateTime.now(),
        approvedAt: DateTime.now(),  // Sofort approved
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

  /// Prüft alle Belohnungen und aktiviert getriggerte
  Future<List<RewardModel>> checkAndApproveRewards({
    required String userId,
    required ChildModel child,
    bool isPerfectQuiz = false,
  }) async {
    try {
      print('🔍 Prüfe Belohnungen für ${child.name}...');

      // Hole alle pending Belohnungen
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

        // Prüfe ob Trigger erfüllt ist
        final isTriggered = reward.isTriggeredBy(
          currentLevel: child.level,
          currentXP: child.xp,
          currentStars: child.stars,
          currentStreak: child.streak ?? 0,
          currentQuizCount: child.totalQuizzes ?? 0,
          isPerfectQuiz: isPerfectQuiz,
        );

        if (isTriggered) {
          // Status auf approved setzen
          await doc.reference.update({
            'status': 'approved',
            'approvedAt': FieldValue.serverTimestamp(),
          });

          print('✅ Belohnung freigeschaltet: ${reward.title}');

          approvedRewards.add(reward.copyWith(
            status: RewardStatus.approved,
            approvedAt: DateTime.now(),
          ));
        }
      }

      return approvedRewards;
    } catch (e) {
      print('❌ Fehler beim Prüfen der Belohnungen: $e');
      return [];
    }
  }

  /// Erstellt System-Belohnungen für Level-Ups
  Future<RewardModel?> createLevelUpReward({
    required String userId,
    required String childId,
    required int level,
  }) async {
    try {
      // Prüfe ob Level-Up Belohnung schon existiert
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
        return null;  // Bereits vorhanden
      }

      return await createSystemReward(
        userId: userId,
        childId: childId,
        title: '🎉 Level $level erreicht!',
        description: 'Du hast Level $level geschafft!',
        reward: _getLevelUpReward(level),
        trigger: RewardTrigger.level,
        requiredLevel: level,
      );
    } catch (e) {
      print('❌ Fehler beim Erstellen der Level-Up Belohnung: $e');
      return null;
    }
  }

  /// Erstellt Perfect-Quiz Belohnung
  Future<RewardModel?> createPerfectQuizReward({
    required String userId,
    required String childId,
  }) async {
    try {
      return await createSystemReward(
        userId: userId,
        childId: childId,
        title: '⭐ Perfekt!',
        description: '10/10 Punkte im Quiz!',
        reward: '1 Bonus-Stern + 25 Extra-XP',
        trigger: RewardTrigger.perfectQuiz,
      );
    } catch (e) {
      print('❌ Fehler beim Erstellen der Perfect-Quiz Belohnung: $e');
      return null;
    }
  }

  /// Löst eine Belohnung ein
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
      });

      print('✅ Belohnung eingelöst!');
    } catch (e) {
      print('❌ Fehler beim Einlösen der Belohnung: $e');
      rethrow;
    }
  }

  /// Holt alle Belohnungen eines Kindes
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
      query = query.where('status', isEqualTo: status.toFirestore()) as Query<Map<String, dynamic>>;
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => RewardModel.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  /// Validiert ob Eltern-Belohnung erstellt werden kann
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

  /// Gibt Belohnung basierend auf Level zurück
  String _getLevelUpReward(int level) {
    if (level <= 3) return '30 Min Extra-Spielzeit';
    if (level <= 5) return '1 Stunde Extra-Spielzeit';
    if (level <= 7) return 'Wunsch-Essen';
    if (level <= 10) return 'Kleines Geschenk';
    return 'Besonderes Erlebnis';
  }
}

/// Validierungs-Ergebnis
class ValidationResult {
  final bool isValid;
  final String message;

  ValidationResult(this.isValid, this.message);
}

/// Provider für Reward Service
final rewardServiceProvider = Provider<RewardService>((ref) {
  return RewardService(FirebaseFirestore.instance);
});