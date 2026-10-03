import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';

const uid = 'parent1';
const cid = 'child1';

CollectionReference<Map<String, dynamic>> rewardsCol(FakeFirebaseFirestore fs) =>
    fs
        .collection('users')
        .doc(uid)
        .collection('children')
        .doc(cid)
        .collection('rewards');

Future<void> addReward(
  FakeFirebaseFirestore fs, {
  required RewardStatus status,
  bool parentSeen = false,
  DateTime? createdAt,
}) async {
  final reward = RewardModel(
    id: '',
    childId: cid,
    title: 'R',
    description: 'd',
    type: RewardType.parent,
    trigger: RewardTrigger.manual,
    status: status,
    reward: 'Eis',
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    createdBy: uid,
    parentSeen: parentSeen,
  );
  await rewardsCol(fs).add(reward.toFirestore());
}

void main() {
  group('createPerfectQuizReward', () {
    test('erstellt eine Perfect-Quiz-Belohnung mit Bonus-XP', () async {
      final fs = FakeFirebaseFirestore();
      final service = RewardService(fs);

      final reward =
          await service.createPerfectQuizReward(userId: uid, childId: cid);

      expect(reward, isNotNull);
      expect(reward!.trigger, RewardTrigger.perfectQuiz);
      expect(reward.bonusXP, 40);
      expect(reward.status, RewardStatus.approved);
    });
  });

  group('markClaimedRewardsAsSeen', () {
    test('setzt parentSeen für ungesehene eingelöste Belohnungen', () async {
      final fs = FakeFirebaseFirestore();
      await addReward(fs, status: RewardStatus.claimed, parentSeen: false);
      await addReward(fs, status: RewardStatus.claimed, parentSeen: true);
      await addReward(fs, status: RewardStatus.pending, parentSeen: false);
      final service = RewardService(fs);

      await service.markClaimedRewardsAsSeen(userId: uid, childId: cid);

      final claimed =
          await rewardsCol(fs).where('status', isEqualTo: 'claimed').get();
      // Alle eingelösten sind jetzt gesehen
      expect(
        claimed.docs.every((d) => d.data()['parentSeen'] == true),
        isTrue,
      );
    });

    test('tut nichts wenn keine ungesehenen vorhanden sind', () async {
      final fs = FakeFirebaseFirestore();
      await addReward(fs, status: RewardStatus.claimed, parentSeen: true);
      final service = RewardService(fs);

      // Darf nicht werfen
      await service.markClaimedRewardsAsSeen(userId: uid, childId: cid);

      final claimed =
          await rewardsCol(fs).where('status', isEqualTo: 'claimed').get();
      expect(claimed.docs.first.data()['parentSeen'], isTrue);
    });
  });

  group('getRewardsStream', () {
    test('liefert alle Belohnungen (nach createdAt absteigend)', () async {
      final fs = FakeFirebaseFirestore();
      await addReward(fs,
          status: RewardStatus.approved, createdAt: DateTime(2026, 1, 1));
      await addReward(fs,
          status: RewardStatus.pending, createdAt: DateTime(2026, 2, 1));
      final service = RewardService(fs);

      final rewards =
          await service.getRewardsStream(userId: uid, childId: cid).first;

      expect(rewards.length, 2);
      // descending → neueste zuerst
      expect(rewards.first.status, RewardStatus.pending);
    });

    test('filtert nach Status wenn angegeben', () async {
      final fs = FakeFirebaseFirestore();
      await addReward(fs, status: RewardStatus.approved);
      await addReward(fs, status: RewardStatus.pending);
      final service = RewardService(fs);

      final approved = await service
          .getRewardsStream(
            userId: uid,
            childId: cid,
            status: RewardStatus.approved,
          )
          .first;

      expect(approved.length, 1);
      expect(approved.first.status, RewardStatus.approved);
    });
  });
}
