import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/data/system_rewards_initializer.dart';

// Belohnungen: nur freigeschaltete sind einlösbar, Bonus-XP gibt es pro
// Belohnung nur einmal, Systembelohnungen werden nicht doppelt angelegt.

const uid = 'parent1';
const cid = 'child1';

late FakeFirebaseFirestore fs;
late RewardService service;

DocumentReference<Map<String, dynamic>> childRef() =>
    fs.collection('users').doc(uid).collection('children').doc(cid);

CollectionReference<Map<String, dynamic>> rewards() =>
    childRef().collection('rewards');

Future<Map<String, dynamic>> childData() async =>
    (await childRef().get()).data()!;

Future<ChildModel> child() async =>
    ChildModel.fromFirestore(await childData(), cid);

Future<void> seedChild({int level = 1, int xp = 0}) => childRef().set({
  'name': 'Max',
  'grade': 3,
  'schoolType': 'Grundschule',
  'age': 9,
  'level': level,
  'xp': xp,
  'stars': 0,
  'streak': 0,
  'totalQuizzes': 0,
});

Future<String> addReward({
  String status = 'pending',
  String trigger = 'level',
  int? requiredLevel = 1,
  int? bonusXP,
  String type = 'parent',
  String createdBy = uid,
  String? id,
}) async {
  final data = {
    'childId': cid,
    'title': 'Eis',
    'description': '',
    'reward': 'Eis essen',
    'type': type,
    'trigger': trigger,
    'requiredLevel': ?requiredLevel,
    'bonusXP': ?bonusXP,
    'status': status,
    'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'createdBy': createdBy,
  };
  if (id != null) {
    await rewards().doc(id).set(data);
    return id;
  }
  return (await rewards().add(data)).id;
}

Future<String> status(String id) async =>
    (await rewards().doc(id).get()).data()!['status'] as String;

void main() {
  setUp(() {
    fs = FakeFirebaseFirestore();
    service = RewardService(fs);
  });

  group('claimReward', () {
    test('gesperrte (pending) Belohnung ist nicht einlösbar', () async {
      await seedChild();
      final id = await addReward(trigger: 'manual', requiredLevel: null);

      await expectLater(
        service.claimReward(userId: uid, childId: cid, rewardId: id),
        throwsA(isA<RewardNotClaimableException>()),
      );
      expect(await status(id), 'pending');
    });

    test('bereits eingelöste Belohnung nicht noch einmal', () async {
      await seedChild();
      final id = await addReward(status: 'claimed');

      await expectLater(
        service.claimReward(userId: uid, childId: cid, rewardId: id),
        throwsA(isA<RewardNotClaimableException>()),
      );
    });

    test('freigeschaltete Belohnung wird eingelöst', () async {
      await seedChild();
      final id = await addReward(status: 'approved');

      await service.claimReward(userId: uid, childId: cid, rewardId: id);
      expect(await status(id), 'claimed');
    });
  });

  group('Bonus-XP nur einmal', () {
    test(
      'Zurückziehen und erneut Freischalten gibt keine Bonus-XP mehr',
      () async {
        await seedChild(level: 2, xp: 100);
        final id = await addReward(requiredLevel: 2, bonusXP: 30);

        await service.checkAndApproveRewards(userId: uid, child: await child());
        expect((await childData())['xp'], 130);
        expect(
          (await childData())[RewardService.grantedBonusField],
          contains(id),
        );

        // Eltern ändern die Bedingung → wieder pending
        await rewards().doc(id).update({'status': 'pending'});
        final approved = await service.checkAndApproveRewards(
          userId: uid,
          child: await child(),
        );

        expect(approved, hasLength(1));
        expect(await status(id), 'approved');
        expect((await childData())['xp'], 130);
      },
    );

    test(
      'zurückgezogene Belohnung wird nicht automatisch freigeschaltet',
      () async {
        await seedChild(level: 5);
        final id = await addReward(requiredLevel: 2);
        await rewards().doc(id).update({'withdrawn': true});

        final approved = await service.checkAndApproveRewards(
          userId: uid,
          child: await child(),
        );

        expect(approved, isEmpty);
        expect(await status(id), 'pending');
      },
    );

    test(
      'zweites Gerät mit altem Stand schaltet nicht noch einmal frei',
      () async {
        await seedChild(level: 2, xp: 100);
        await addReward(requiredLevel: 2, bonusXP: 30);
        final stale = await child();

        final first = await service.checkAndApproveRewards(
          userId: uid,
          child: stale,
        );
        final second = await service.checkAndApproveRewards(
          userId: uid,
          child: stale,
        );

        expect(first, hasLength(1));
        expect(second, isEmpty);
        expect((await childData())['xp'], 130);
      },
    );
  });

  group('Systembelohnungen beim Level-Up', () {
    test(
      'Level ohne vordefinierte Belohnung: Bonus-XP werden gutgeschrieben',
      () async {
        await seedChild(level: 4, xp: 400);

        final reward = await service.createLevelUpReward(
          userId: uid,
          childId: cid,
          level: 4,
        );

        expect(reward, isNotNull);
        final doc = await rewards().doc('sys_level_4').get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['status'], 'approved');
        expect(doc.data()!['badgeId'], 'badge-level-4');
        expect((await childData())['xp'], 450);

        // Zweiter Aufruf (z.B. anderes Gerät): kein Duplikat, keine XP
        final again = await service.createLevelUpReward(
          userId: uid,
          childId: cid,
          level: 4,
        );
        expect(again, isNull);
        expect((await rewards().get()).docs, hasLength(1));
        expect((await childData())['xp'], 450);
      },
    );

    test('ältere Systembelohnung mit zufälliger ID wird verwendet', () async {
      await seedChild(level: 5, xp: 200);
      final id = await addReward(
        requiredLevel: 5,
        bonusXP: 100,
        type: 'parent', // von den Eltern bearbeitet
        createdBy: 'system',
      );

      final reward = await service.createLevelUpReward(
        userId: uid,
        childId: cid,
        level: 5,
      );

      expect(reward?.id, id);
      expect((await rewards().get()).docs, hasLength(1));
      expect((await childData())['xp'], 300);
    });

    test('perfektes Quiz: +40 XP einmal', () async {
      await seedChild(xp: 10);

      await service.createPerfectQuizReward(userId: uid, childId: cid);
      await service.createPerfectQuizReward(userId: uid, childId: cid);

      expect((await childData())['xp'], 50);
      final doc = await rewards().doc(RewardService.perfectQuizRewardId).get();
      expect(doc.data()!['badgeId'], 'badge-perfect-quiz');
    });
  });

  group('SystemRewardsInitializer', () {
    test('neue Kinder bekommen feste IDs', () async {
      final init = SystemRewardsInitializer(fs);
      await init.initializeSystemRewards(userId: uid, childId: cid);

      expect((await rewards().doc('sys_level_2').get()).exists, isTrue);
      expect((await rewards().doc('sys_xp_100').get()).exists, isTrue);
      expect((await rewards().doc('sys_streak_7').get()).exists, isTrue);
      expect((await rewards().doc('sys_quiz_count_10').get()).exists, isTrue);
      expect((await rewards().doc('sys_perfect_quiz').get()).exists, isTrue);
    });

    test('bearbeitete Systembelohnung wird nicht neu angelegt', () async {
      final init = SystemRewardsInitializer(fs);
      await init.initializeSystemRewards(userId: uid, childId: cid);
      final before = (await rewards().get()).docs.length;

      await rewards().doc('sys_level_2').update({
        'title': 'Eigener Titel',
        'type': 'parent',
        'requiredLevel': 4,
      });
      await init.addMissingSystemRewards(userId: uid, childId: cid);

      expect((await rewards().get()).docs, hasLength(before));
    });

    test(
      'ältere Kinder (zufällige IDs, bearbeitet) bekommen keine Dubletten',
      () async {
        final init = SystemRewardsInitializer(fs);
        await init.initializeSystemRewards(userId: uid, childId: cid);
        final all = await rewards().get();

        // Stand vor den festen IDs nachstellen: gleiche Daten, zufällige IDs
        for (final doc in all.docs) {
          final data = doc.data();
          await doc.reference.delete();
          if (doc.id == 'sys_level_2') {
            data['title'] = 'Eigener Titel';
            data['type'] = 'parent';
            data['requiredLevel'] = 4;
          }
          await rewards().add(data);
        }

        await init.addMissingSystemRewards(userId: uid, childId: cid);
        await init.addMissingSystemRewards(userId: uid, childId: cid);

        expect((await rewards().get()).docs, hasLength(all.docs.length));
      },
    );

    test('fehlende werden mit fester ID ergänzt, vorhandene bleiben', () async {
      final init = SystemRewardsInitializer(fs);
      await init.initializeSystemRewards(userId: uid, childId: cid);
      await rewards().doc('sys_xp_100').delete();
      await rewards().doc('sys_level_3').update({'status': 'claimed'});
      final count = (await rewards().get()).docs.length;

      await init.addMissingSystemRewards(userId: uid, childId: cid);

      expect((await rewards().get()).docs, hasLength(count + 1));
      expect((await rewards().doc('sys_xp_100').get()).exists, isTrue);
      expect(await status('sys_level_3'), 'claimed');
    });
  });
}
