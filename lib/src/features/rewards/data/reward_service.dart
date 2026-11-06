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
  XPService? _xpService;
  XPService get _xp => _xpService ??= XPService(_firestore);

  /// Feld am Kind-Dokument: IDs der Belohnungen, deren Bonus-XP schon
  /// gutgeschrieben wurden. Liegt am Kind (nicht an der Belohnung), weil das
  /// Kindergerät an Belohnungen nur Status-Felder ändern darf. So gibt es die
  /// Bonus-XP pro Belohnung nur einmal – auch wenn Eltern sie zurückziehen
  /// und wieder freigeben oder die Bedingung ändern.
  static const grantedBonusField = 'grantedBonusRewardIds';

  /// Feste Dokument-ID der Level-Belohnung (wie im SystemRewardsInitializer)
  static String levelRewardId(int level) => 'sys_level_$level';

  /// Feste Dokument-ID der Belohnung für ein perfektes Quiz
  static const perfectQuizRewardId = 'sys_perfect_quiz';

  DocumentReference<Map<String, dynamic>> _childRef(
    String userId,
    String childId,
  ) => _firestore
      .collection('users')
      .doc(userId)
      .collection('children')
      .doc(childId);

  CollectionReference<Map<String, dynamic>> _rewardsCol(
    String userId,
    String childId,
  ) => _childRef(userId, childId).collection('rewards');

  /// Bonus-XP (einmalig) und Avatar einer gerade freigeschalteten Belohnung
  /// in derselben Transaktion ans Kind schreiben. Gibt zurück, ob Bonus-XP
  /// gutgeschrieben wurden.
  bool _applyRewardToChild(
    Transaction tx,
    DocumentSnapshot<Map<String, dynamic>> childSnap,
    RewardModel reward,
  ) {
    final childData = childSnap.data();
    if (childData == null) return false;

    final updates = <String, dynamic>{};
    var bonusGiven = false;

    final bonus = reward.bonusXP ?? 0;
    final granted = List<String>.from(
      childData[grantedBonusField] as List? ?? const [],
    );
    if (bonus > 0 && !granted.contains(reward.id)) {
      updates.addAll(XPService.xpGainFields(childData, bonus).fields);
      updates[grantedBonusField] = FieldValue.arrayUnion([reward.id]);
      bonusGiven = true;
    }

    if (reward.avatarUnlockId != null) {
      updates['unlockedAvatars'] = FieldValue.arrayUnion([
        reward.avatarUnlockId!,
      ]);
    }

    if (updates.isNotEmpty) tx.update(childSnap.reference, updates);
    return bonusGiven;
  }

  /// Schaltet eine Belohnung frei, wenn sie noch `pending` (und nicht von
  /// den Eltern zurückgezogen) ist – in einer Transaktion, damit zwei Geräte
  /// gleichzeitig sie nur einmal freischalten. Sonst null.
  Future<({RewardModel reward, bool bonusGiven})?> _approveIfPending({
    required String userId,
    required String childId,
    required DocumentReference<Map<String, dynamic>> rewardRef,
  }) {
    final childRef = _childRef(userId, childId);
    return _firestore.runTransaction((tx) async {
      final rewardSnap = await tx.get(rewardRef);
      final childSnap = await tx.get(childRef);
      final data = rewardSnap.data();
      if (data == null) return null;

      final reward = RewardModel.fromFirestore(data, rewardSnap.id);
      if (reward.status != RewardStatus.pending || reward.withdrawn) {
        return null;
      }

      tx.update(rewardRef, {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });
      final bonusGiven = _applyRewardToChild(tx, childSnap, reward);

      return (
        reward: reward.copyWith(
          status: RewardStatus.approved,
          approvedAt: DateTime.now(),
        ),
        bonusGiven: bonusGiven,
      );
    });
  }

  /// Erstellt eine System-Belohnung (automatisch approved) und schreibt
  /// Bonus-XP und Avatar in derselben Transaktion gut.
  ///
  /// Mit [docId] (feste ID, z.B. `sys_level_4`) wird nur angelegt, wenn es
  /// das Dokument noch nicht gibt – sonst null.
  Future<RewardModel?> createSystemReward({
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
    String? docId,
  }) async {
    try {
      final col = _rewardsCol(userId, childId);
      final ref = docId != null ? col.doc(docId) : col.doc();
      final childRef = _childRef(userId, childId);

      final rewardData = RewardModel(
        id: ref.id,
        childId: childId,
        title: title,
        description: description,
        type: RewardType.system,
        trigger: trigger,
        requiredLevel: requiredLevel,
        bonusXP: bonusXP,
        avatarUnlockId: avatarUnlockId,
        badgeId: badgeId,
        status: RewardStatus.approved,
        reward: reward,
        createdAt: DateTime.now(),
        approvedAt: DateTime.now(),
        createdBy: 'system',
      );

      final created = await _firestore.runTransaction<RewardModel?>((tx) async {
        final childSnap = await tx.get(childRef);
        if (docId != null && (await tx.get(ref)).exists) return null;

        tx.set(ref, rewardData.toFirestore());
        _applyRewardToChild(tx, childSnap, rewardData);
        return rewardData;
      });

      if (created != null) debugPrint('✅ System-Belohnung erstellt: $title');
      return created;
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
        final snapshot = await _rewardsCol(
          userId,
          currentChild.id,
        ).where('status', isEqualTo: 'pending').get();

        if (snapshot.docs.isEmpty) break;

        bool bonusXpAwarded = false;

        for (var doc in snapshot.docs) {
          final reward = RewardModel.fromFirestore(doc.data(), doc.id);
          if (reward.withdrawn) continue;

          final isTriggered = reward.isTriggeredBy(
            currentLevel: currentChild.level,
            currentXP: currentChild.xp,
            currentStars: currentChild.stars,
            currentStreak: currentChild.streak ?? 0,
            currentQuizCount: currentChild.totalQuizzes ?? 0,
            isPerfectQuiz: isPerfectQuiz && pass == 0,
          );
          if (!isTriggered) continue;

          try {
            final result = await _approveIfPending(
              userId: userId,
              childId: currentChild.id,
              rewardRef: doc.reference,
            );
            if (result == null) continue; // anderes Gerät war schneller

            debugPrint('✅ Belohnung freigeschaltet: ${reward.title}');
            if (result.bonusGiven) {
              debugPrint('⚡ +${reward.bonusXP} Bonus-XP vergeben');
              bonusXpAwarded = true;
            }
            allApproved.add(result.reward);
          } catch (e) {
            debugPrint('❌ Fehler beim Freischalten von ${reward.title}: $e');
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

  /// Systembelohnung mit fester ID freischalten oder – wenn es sie noch
  /// nicht gibt – anlegen. Ältere Kinder haben Systembelohnungen mit
  /// zufälliger ID; die findet [legacyQuery] (davon zählen nur
  /// Systembelohnungen, auch wenn die Eltern sie bearbeitet haben).
  Future<RewardModel?> _approveOrCreateSystemReward({
    required String userId,
    required String childId,
    required String docId,
    required Query<Map<String, dynamic>> legacyQuery,
    required Future<RewardModel?> Function() create,
  }) async {
    final fixedRef = _rewardsCol(userId, childId).doc(docId);
    final fixedSnap = await fixedRef.get();

    DocumentReference<Map<String, dynamic>>? existingRef;
    if (fixedSnap.exists) {
      existingRef = fixedRef;
    } else {
      final legacy = await legacyQuery.get();
      for (final doc in legacy.docs) {
        final data = doc.data();
        if (data['type'] == 'system' || data['createdBy'] == 'system') {
          existingRef = doc.reference;
          break;
        }
      }
    }

    if (existingRef != null) {
      final result = await _approveIfPending(
        userId: userId,
        childId: childId,
        rewardRef: existingRef,
      );
      return result?.reward;
    }

    return create();
  }

  /// Schaltet die Level-Up-Belohnung für ein bestimmtes Level frei.
  ///
  /// • Existiert bereits ein `pending`-Reward → wird direkt approved + zurückgegeben.
  /// • Existiert bereits ein `approved`/`claimed`-Reward → kein Duplikat, null.
  /// • Existiert noch keiner → neuer Reward wird erstellt (Fallback für nicht
  ///   vordefinierte Level wie 4, 6, 8 …).
  /// Bonus-XP gibt es in jedem Fall nur einmal.
  Future<RewardModel?> createLevelUpReward({
    required String userId,
    required String childId,
    required int level,
  }) async {
    try {
      final xpBonus = _getLevelUpBonusXP(level);
      return await _approveOrCreateSystemReward(
        userId: userId,
        childId: childId,
        docId: levelRewardId(level),
        legacyQuery: _rewardsCol(userId, childId)
            .where('trigger', isEqualTo: 'level')
            .where('requiredLevel', isEqualTo: level),
        create: () => createSystemReward(
          userId: userId,
          childId: childId,
          title: '🎉 Level $level erreicht!',
          description: 'Du hast Level $level geschafft – weiter so!',
          reward: '+$xpBonus Bonus-XP',
          trigger: RewardTrigger.level,
          requiredLevel: level,
          bonusXP: xpBonus,
          badgeId: 'badge-level-$level',
          docId: levelRewardId(level),
        ),
      );
    } catch (e) {
      debugPrint('❌ Fehler beim Freischalten der Level-Up Belohnung: $e');
      return null;
    }
  }

  /// Schaltet die Perfect-Quiz-Systembelohnung frei (rein digital, einmalig).
  Future<RewardModel?> createPerfectQuizReward({
    required String userId,
    required String childId,
  }) async {
    try {
      return await _approveOrCreateSystemReward(
        userId: userId,
        childId: childId,
        docId: perfectQuizRewardId,
        legacyQuery: _rewardsCol(
          userId,
          childId,
        ).where('trigger', isEqualTo: 'perfect_quiz'),
        create: () => createSystemReward(
          userId: userId,
          childId: childId,
          title: '⭐ Perfektes Quiz!',
          description: 'Alle Fragen auf Anhieb richtig beantwortet!',
          reward: '+40 Bonus-XP & Badge „Perfektionist"',
          trigger: RewardTrigger.perfectQuiz,
          bonusXP: 40,
          badgeId: 'badge-perfect-quiz',
          docId: perfectQuizRewardId,
        ),
      );
    } catch (e) {
      debugPrint('❌ Fehler beim Erstellen der Perfect-Quiz Belohnung: $e');
      return null;
    }
  }

  /// Löst eine Belohnung ein (setzt parentSeen = false → Eltern werden
  /// informiert). Nur freigeschaltete (`approved`) Belohnungen sind
  /// einlösbar, sonst [RewardNotClaimableException].
  Future<void> claimReward({
    required String userId,
    required String childId,
    required String rewardId,
  }) async {
    try {
      final ref = _rewardsCol(userId, childId).doc(rewardId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.data()?['status'] != 'approved') {
          throw const RewardNotClaimableException();
        }
        tx.update(ref, {
          'status': 'claimed',
          'claimedAt': FieldValue.serverTimestamp(),
          'parentSeen': false,
        });
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
      final snapshot = await _rewardsCol(
        userId,
        childId,
      ).where('status', isEqualTo: 'claimed').get();

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
    Query<Map<String, dynamic>> query = _rewardsCol(
      userId,
      childId,
    ).orderBy('createdAt', descending: true);

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

/// Die Belohnung ist (nicht mehr) freigeschaltet, z.B. weil die Eltern sie
/// zurückgezogen haben oder sie schon eingelöst wurde.
class RewardNotClaimableException implements Exception {
  const RewardNotClaimableException();

  @override
  String toString() => 'Diese Belohnung ist gerade nicht einlösbar.';
}

/// Provider für Reward Service
final rewardServiceProvider = Provider<RewardService>((ref) {
  return RewardService(FirebaseFirestore.instance);
});

/// Belohnungen eines Kindes als Stream, von Riverpod zwischengespeichert:
/// Widgets bekommen bei jedem build() dieselbe Abfrage statt einer neuen
/// Anmeldung (kein Flackern, keine doppelten Lesevorgänge).
final rewardsStreamProvider = StreamProvider.autoDispose
    .family<List<RewardModel>, ({String userId, String childId})>(
      (ref, key) => ref
          .watch(rewardServiceProvider)
          .getRewardsStream(userId: key.userId, childId: key.childId),
    );
