import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';

const uid = 'parent1';
const cid = 'child1';

ChildModel childModel({
  int level = 5,
  int xp = 200,
  int stars = 0,
  int streak = 0,
  int totalQuizzes = 0,
}) {
  return ChildModel(
    id: cid,
    name: 'Max',
    grade: 3,
    schoolType: 'Grundschule',
    age: 9,
    level: level,
    xp: xp,
    stars: stars,
    streak: streak,
    totalQuizzes: totalQuizzes,
  );
}

Future<void> seedChild(FakeFirebaseFirestore fs, ChildModel child) async {
  await fs
      .collection('users')
      .doc(uid)
      .collection('children')
      .doc(cid)
      .set(child.toMap());
}

Future<String> addPendingReward(
  FakeFirebaseFirestore fs, {
  required RewardTrigger trigger,
  int? requiredLevel,
  int? requiredXP,
  int? baselineXP,
  int? bonusXP,
  String? avatarUnlockId,
  RewardType type = RewardType.parent,
}) async {
  final reward = RewardModel(
    id: '',
    childId: cid,
    title: 'Belohnung',
    description: 'd',
    type: type,
    trigger: trigger,
    requiredLevel: requiredLevel,
    requiredXP: requiredXP,
    baselineXP: baselineXP,
    bonusXP: bonusXP,
    avatarUnlockId: avatarUnlockId,
    status: RewardStatus.pending,
    reward: 'Eis',
    createdAt: DateTime(2026, 1, 1),
    createdBy: uid,
  );
  final ref = await fs
      .collection('users')
      .doc(uid)
      .collection('children')
      .doc(cid)
      .collection('rewards')
      .add(reward.toFirestore());
  return ref.id;
}

Future<Map<String, dynamic>> rewardData(
  FakeFirebaseFirestore fs,
  String rewardId,
) async {
  final doc = await fs
      .collection('users')
      .doc(uid)
      .collection('children')
      .doc(cid)
      .collection('rewards')
      .doc(rewardId)
      .get();
  return doc.data()!;
}

void main() {
  group('checkAndApproveRewards', () {
    test('genügte Eltern-Belohnung (Level) wird freigeschaltet', () async {
      final fs = FakeFirebaseFirestore();
      final child = childModel(level: 5);
      await seedChild(fs, child);
      final rewardId =
          await addPendingReward(fs, trigger: RewardTrigger.level, requiredLevel: 5);
      final service = RewardService(fs);

      final approved =
          await service.checkAndApproveRewards(userId: uid, child: child);

      expect(approved.length, 1);
      expect(approved.first.status, RewardStatus.approved);
      expect((await rewardData(fs, rewardId))['status'], 'approved');
    });

    test('nicht erfüllte Belohnung bleibt pending', () async {
      final fs = FakeFirebaseFirestore();
      final child = childModel(level: 5);
      await seedChild(fs, child);
      final rewardId = await addPendingReward(fs,
          trigger: RewardTrigger.level, requiredLevel: 10);
      final service = RewardService(fs);

      final approved =
          await service.checkAndApproveRewards(userId: uid, child: child);

      expect(approved, isEmpty);
      expect((await rewardData(fs, rewardId))['status'], 'pending');
    });

    test('Zwei-Pass: Bonus-XP schaltet eine weitere XP-Belohnung frei',
        () async {
      final fs = FakeFirebaseFirestore();
      final child = childModel(level: 1, xp: 0);
      await seedChild(fs, child);

      // A: perfektes Quiz → +100 Bonus-XP
      await addPendingReward(fs,
          trigger: RewardTrigger.perfectQuiz, bonusXP: 100);
      // B: ab 100 XP (wird erst nach Bonus-XP aus A erfüllt)
      await addPendingReward(fs,
          trigger: RewardTrigger.xp, requiredXP: 100, baselineXP: 0);

      final service = RewardService(fs);
      final approved = await service.checkAndApproveRewards(
        userId: uid,
        child: child,
        isPerfectQuiz: true,
      );

      // Beide Belohnungen müssen freigeschaltet sein
      expect(approved.length, 2);
      // Kind hat die Bonus-XP erhalten
      final stored = (await fs
              .collection('users')
              .doc(uid)
              .collection('children')
              .doc(cid)
              .get())
          .data()!;
      expect(stored['xp'], 100);
    });

    test('Avatar-Belohnung schaltet Avatar am Kind frei', () async {
      final fs = FakeFirebaseFirestore();
      final child = childModel(level: 5);
      await seedChild(fs, child);
      await addPendingReward(fs,
          trigger: RewardTrigger.level,
          requiredLevel: 5,
          avatarUnlockId: 'avatar-rare');
      final service = RewardService(fs);

      await service.checkAndApproveRewards(userId: uid, child: child);

      final stored = (await fs
              .collection('users')
              .doc(uid)
              .collection('children')
              .doc(cid)
              .get())
          .data()!;
      expect(
        List<String>.from(stored['unlockedAvatars'] ?? []),
        contains('avatar-rare'),
      );
    });

    test('manuelle Belohnung wird nie automatisch freigeschaltet', () async {
      final fs = FakeFirebaseFirestore();
      final child = childModel(level: 50, xp: 99999);
      await seedChild(fs, child);
      final rewardId =
          await addPendingReward(fs, trigger: RewardTrigger.manual);
      final service = RewardService(fs);

      final approved =
          await service.checkAndApproveRewards(userId: uid, child: child);

      expect(approved, isEmpty);
      expect((await rewardData(fs, rewardId))['status'], 'pending');
    });
  });

  group('validateParentReward', () {
    final service = RewardService(FakeFirebaseFirestore());
    final child = childModel(level: 5, stars: 3);

    test('Level: muss höher als aktuelles Level sein', () {
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.level, requiredLevel: null)
            .isValid,
        isFalse,
      );
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.level, requiredLevel: 5)
            .isValid,
        isFalse,
      );
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.level, requiredLevel: 6)
            .isValid,
        isTrue,
      );
    });

    test('XP: muss > 0 und gesetzt sein', () {
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.xp, requiredXP: null)
            .isValid,
        isFalse,
      );
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.xp, requiredXP: 0)
            .isValid,
        isFalse,
      );
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.xp, requiredXP: 100)
            .isValid,
        isTrue,
      );
    });

    test('Sterne: muss mehr als aktuelle Sterne sein', () {
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.stars, requiredStars: 3)
            .isValid,
        isFalse,
      );
      expect(
        service
            .validateParentReward(
                child: child, trigger: RewardTrigger.stars, requiredStars: 5)
            .isValid,
        isTrue,
      );
    });

    test('manuelle/sonstige Trigger sind immer valide', () {
      expect(
        service
            .validateParentReward(child: child, trigger: RewardTrigger.manual)
            .isValid,
        isTrue,
      );
    });
  });

  group('createSystemReward', () {
    test('erstellt eine sofort freigegebene Belohnung mit ID', () async {
      final fs = FakeFirebaseFirestore();
      final service = RewardService(fs);

      final reward = await service.createSystemReward(
        userId: uid,
        childId: cid,
        title: 'Titel',
        description: 'd',
        reward: 'Badge',
        trigger: RewardTrigger.perfectQuiz,
        bonusXP: 40,
      );

      expect(reward.id, isNotEmpty);
      expect(reward.status, RewardStatus.approved);
      expect((await rewardData(fs, reward.id))['status'], 'approved');
    });
  });

  group('createLevelUpReward', () {
    test('approved bestehende pending Belohnung und vergibt Bonus-XP',
        () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, childModel(level: 5, xp: 200));
      final rewardId = await addPendingReward(fs,
          trigger: RewardTrigger.level,
          requiredLevel: 5,
          bonusXP: 50,
          type: RewardType.system);
      final service = RewardService(fs);

      final result = await service.createLevelUpReward(
          userId: uid, childId: cid, level: 5);

      expect(result, isNotNull);
      expect(result!.status, RewardStatus.approved);
      expect((await rewardData(fs, rewardId))['status'], 'approved');
      // Bonus-XP wurde dem Kind gutgeschrieben
      final stored = (await fs
              .collection('users')
              .doc(uid)
              .collection('children')
              .doc(cid)
              .get())
          .data()!;
      expect(stored['xp'], 250);
    });

    test('kein Duplikat bei bereits freigeschalteter Belohnung', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, childModel(level: 5));
      // bereits approved
      final reward = RewardModel(
        id: '',
        childId: cid,
        title: 't',
        description: 'd',
        type: RewardType.system,
        trigger: RewardTrigger.level,
        requiredLevel: 5,
        status: RewardStatus.approved,
        reward: 'x',
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'system',
      );
      await fs
          .collection('users')
          .doc(uid)
          .collection('children')
          .doc(cid)
          .collection('rewards')
          .add(reward.toFirestore());
      final service = RewardService(fs);

      final result = await service.createLevelUpReward(
          userId: uid, childId: cid, level: 5);
      expect(result, isNull);
    });

    test('erstellt dynamische Belohnung wenn keine existiert', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, childModel(level: 4));
      final service = RewardService(fs);

      final result = await service.createLevelUpReward(
          userId: uid, childId: cid, level: 4);

      expect(result, isNotNull);
      expect(result!.trigger, RewardTrigger.level);
      expect(result.requiredLevel, 4);
      expect(result.bonusXP, 50); // _getLevelUpBonusXP(4)
    });
  });

  group('claimReward', () {
    test('setzt Status claimed und parentSeen=false', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, childModel());
      final rewardId =
          await addPendingReward(fs, trigger: RewardTrigger.manual);
      final service = RewardService(fs);

      await service.claimReward(userId: uid, childId: cid, rewardId: rewardId);

      final data = await rewardData(fs, rewardId);
      expect(data['status'], 'claimed');
      expect(data['parentSeen'], isFalse);
    });
  });
}
