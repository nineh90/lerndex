import 'package:flutter/foundation.dart';
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

  /// Lazy XPService – vermeidet wiederholte Instanziierung.
  /// ⚠️ FIX: Vorher stand hier `_xpService ??= _xp` was zu einer endlosen
  /// Rekursion (StackOverflowError) führte, sobald `addXP` oder `getChild`
  /// aufgerufen wurde. Das hatte zur Folge, dass `checkAndApproveRewards`
  /// stillschweigend gefangen wurde und Eltern-Belohnungen mit Trigger
  /// (Level/XP/Streak) nie auf 'approved' gesetzt wurden — wodurch sie für
  /// das Kind unsichtbar blieben.
  XPService? _xpService;
  XPService get _xp => _xpService ??= XPService(_firestore);

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

      debugPrint('✅ System-Belohnung erstellt: $title');
      return rewardData.copyWith(id: docRef.id);
    } catch (e) {
      debugPrint('❌ Fehler beim Erstellen der System-Belohnung: $e');
      rethrow;
    }
  }

  /// Prüft alle pending Belohnungen und aktiviert getriggerte.
  /// Nach Bonus-XP-Vergabe wird automatisch ein zweiter Durchlauf gemacht,
  /// damit z.B. ein Level-Up durch Bonus-XP sofort weitere Rewards triggert.
  Future<List<RewardModel>> checkAndApproveRewards({
    required String userId,
    required ChildModel child,
    bool isPerfectQuiz = false,
  }) async {
    try {
      debugPrint('🔍 Prüfe Belohnungen für ${child.name}...');

      final allApproved = <RewardModel>[];

      // Maximal 2 Durchläufe: erster mit dem übergebenen Kind,
      // zweiter (falls Bonus-XP Level/XP verändert haben) mit frisch
      // geladenem Kind aus Firestore.
      ChildModel currentChild = child;

      for (int pass = 0; pass < 2; pass++) {
        final snapshot = await _firestore
            .collection('users')
            .doc(userId)
            .collection('children')
            .doc(currentChild.id)
            .collection('rewards')
            .where('status', isEqualTo: 'pending')
            .get();

        if (snapshot.docs.isEmpty) break;

        bool bonusXpAwarded = false;

        for (var doc in snapshot.docs) {
          final reward = RewardModel.fromFirestore(doc.data(), doc.id);

          final isTriggered = reward.isTriggeredBy(
            currentLevel: currentChild.level,
            currentXP: currentChild.xp,
            currentStars: currentChild.stars,
            currentStreak: currentChild.streak ?? 0,
            currentQuizCount: currentChild.totalQuizzes ?? 0,
            isPerfectQuiz: isPerfectQuiz && pass == 0,
          );

          if (isTriggered) {
            await doc.reference.update({
              'status': 'approved',
              'approvedAt': FieldValue.serverTimestamp(),
            });

            debugPrint('✅ Belohnung freigeschaltet: ${reward.title}');

            // ⚡ Bonus-XP automatisch vergeben
            if (reward.bonusXP != null && reward.bonusXP! > 0) {
              try {
                await _xp.addXP(
                  userId: userId,
                  childId: currentChild.id,
                  xpToAdd: reward.bonusXP!,
                );
                debugPrint('⚡ +${reward.bonusXP} Bonus-XP vergeben');
                bonusXpAwarded = true;
              } catch (e) {
                debugPrint('❌ Fehler beim Vergeben von Bonus-XP: $e');
              }
            }

            // 🎭 Avatar automatisch freischalten
            if (reward.avatarUnlockId != null) {
              try {
                await _firestore
                    .collection('users')
                    .doc(userId)
                    .collection('children')
                    .doc(currentChild.id)
                    .update({
                      'unlockedAvatars': FieldValue.arrayUnion([
                        reward.avatarUnlockId!,
                      ]),
                    });
                debugPrint(
                  '🎭 Avatar freigeschaltet: ${reward.avatarUnlockId}',
                );
              } catch (e) {
                debugPrint('❌ Fehler beim Freischalten des Avatars: $e');
              }
            }

            allApproved.add(
              reward.copyWith(
                status: RewardStatus.approved,
                approvedAt: DateTime.now(),
              ),
            );
          }
        }

        // Zweiter Durchlauf nur wenn Bonus-XP vergeben wurden
        // (könnte Level/XP-Schwelle für weitere Rewards überschritten haben)
        if (!bonusXpAwarded) break;

        // Kind neu laden mit aktualisierten XP/Level-Werten
        final refreshed = await _xp.getChild(
          userId: userId,
          childId: currentChild.id,
        );
        if (refreshed == null) break;
        currentChild = refreshed;
        debugPrint(
          '🔄 Zweiter Reward-Check nach Bonus-XP '
          '(Level ${currentChild.level}, ${currentChild.xp} XP)',
        );
      }

      return allApproved;
    } catch (e) {
      debugPrint('❌ Fehler beim Prüfen der Belohnungen: $e');
      return [];
    }
  }

  /// Schaltet die Level-Up-Belohnung für ein bestimmtes Level frei.
  ///
  /// • Existiert bereits ein `pending`-Reward → wird direkt approved + zurückgegeben.
  /// • Existiert bereits ein `approved`/`claimed`-Reward → kein Duplikat, null.
  /// • Existiert noch keiner → neuer Reward wird erstellt (Fallback für nicht
  ///   vordefinierte Level wie 4, 6, 8 …).
  Future<RewardModel?> createLevelUpReward({
    required String userId,
    required String childId,
    required int level,
  }) async {
    try {
      final snapshot = await _firestore
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

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final existing = RewardModel.fromFirestore(doc.data(), doc.id);

        // Bereits approved oder claimed → nichts tun
        if (existing.status != RewardStatus.pending) {
          debugPrint('ℹ️ Level-$level-Belohnung bereits freigeschaltet');
          return null;
        }

        // Pending → jetzt approven + Bonus-XP vergeben
        await doc.reference.update({
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
        });

        if (existing.bonusXP != null && existing.bonusXP! > 0) {
          try {
            await _xp.addXP(
              userId: userId,
              childId: childId,
              xpToAdd: existing.bonusXP!,
            );
            debugPrint(
              '⚡ +${existing.bonusXP} Bonus-XP für Level $level vergeben',
            );
          } catch (e) {
            debugPrint('❌ Fehler beim Vergeben von Bonus-XP: $e');
          }
        }

        debugPrint('✅ Level-$level-Belohnung aus pending approved');
        return existing.copyWith(
          status: RewardStatus.approved,
          approvedAt: DateTime.now(),
        );
      }

      // Kein Reward vorhanden → dynamisch erstellen (z.B. Level 4, 6, 8 …)
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
      debugPrint('❌ Fehler beim Freischalten der Level-Up Belohnung: $e');
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
      debugPrint('❌ Fehler beim Erstellen der Perfect-Quiz Belohnung: $e');
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

      debugPrint('✅ Belohnung eingelöst!');
    } catch (e) {
      debugPrint('❌ Fehler beim Einlösen der Belohnung: $e');
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
      debugPrint('✅ ${unseen.length} Belohnungen als gesehen markiert');
    } catch (e) {
      debugPrint('❌ Fehler beim Markieren als gesehen: $e');
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
        if (requiredXP <= 0) {
          return ValidationResult(false, 'XP muss größer als 0 sein');
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
