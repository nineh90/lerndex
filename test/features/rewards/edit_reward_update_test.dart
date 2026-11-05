import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';
import 'package:lerndex/src/features/rewards/presentation/widgets/edit_reward_dialog.dart';

RewardModel reward({
  RewardTrigger trigger = RewardTrigger.level,
  int? requiredLevel = 5,
  int? requiredXP,
  int? baselineXP,
  RewardStatus status = RewardStatus.approved,
}) => RewardModel(
  id: 'r1',
  childId: 'c1',
  title: 'Eis',
  description: '',
  type: RewardType.parent,
  trigger: trigger,
  requiredLevel: requiredLevel,
  requiredXP: requiredXP,
  baselineXP: baselineXP,
  bonusXP: 30,
  status: status,
  reward: 'Eis essen',
  createdAt: DateTime(2026, 1, 1),
  createdBy: 'u1',
);

/// Wendet das Update auf ein gespeichertes Dokument an und liest es zurück.
Future<RewardModel> save(
  RewardModel original,
  Map<String, dynamic> update,
) async {
  final fs = FakeFirebaseFirestore();
  final ref = fs.collection('rewards').doc(original.id);
  await ref.set(original.toFirestore());
  await ref.update(update);
  final data = (await ref.get()).data()!;
  return RewardModel.fromFirestore(data, ref.id);
}

void main() {
  test('nur Text geändert: Status, Bedingung und Typ bleiben', () async {
    final original = reward(status: RewardStatus.claimed);
    final update = buildRewardEditUpdate(
      original: original,
      currentXP: 500,
      title: 'Großes Eis',
      description: 'neu',
      reward: 'Eis essen',
      trigger: RewardTrigger.level,
      triggerValue: 5,
    );

    expect(update.containsKey('status'), isFalse);
    expect(update.containsKey('type'), isFalse);
    final saved = await save(original, update);
    expect(saved.title, 'Großes Eis');
    expect(saved.status, RewardStatus.claimed);
    expect(saved.requiredLevel, 5);
  });

  test('XP-Ziel unverändert: Startwert bleibt', () async {
    final original = reward(
      trigger: RewardTrigger.xp,
      requiredLevel: null,
      requiredXP: 100,
      baselineXP: 200,
    );
    final update = buildRewardEditUpdate(
      original: original,
      currentXP: 900,
      title: 'Eis',
      description: '',
      reward: 'Eis essen',
      trigger: RewardTrigger.xp,
      triggerValue: 100,
    );

    final saved = await save(original, update);
    expect(saved.baselineXP, 200);
    expect(saved.status, RewardStatus.approved);
  });

  test('Wechsel auf XP: zählt ab jetzt, Status wieder gesperrt', () async {
    final original = reward();
    final update = buildRewardEditUpdate(
      original: original,
      currentXP: 900,
      title: 'Eis',
      description: '',
      reward: 'Eis essen',
      trigger: RewardTrigger.xp,
      triggerValue: 100,
    );

    final saved = await save(original, update);
    expect(saved.status, RewardStatus.pending);
    expect(saved.trigger, RewardTrigger.xp);
    expect(saved.requiredXP, 100);
    expect(saved.requiredLevel, isNull);
    expect(saved.baselineXP, 900);
    // löst nicht sofort aus
    expect(
      saved.isTriggeredBy(
        currentLevel: 10,
        currentXP: 900,
        currentStars: 0,
        currentStreak: 0,
        currentQuizCount: 0,
      ),
      isFalse,
    );
  });

  test('neues Level-Ziel: gesperrt, Zurückziehen aufgehoben', () async {
    final original = reward(status: RewardStatus.pending);
    final stored = original.toFirestore()..['withdrawn'] = true;
    final fs = FakeFirebaseFirestore();
    final ref = fs.collection('rewards').doc('r1');
    await ref.set(stored);

    await ref.update(
      buildRewardEditUpdate(
        original: original,
        currentXP: 0,
        title: 'Eis',
        description: '',
        reward: 'Eis essen',
        trigger: RewardTrigger.level,
        triggerValue: 7,
      ),
    );

    final data = (await ref.get()).data()!;
    expect(data['requiredLevel'], 7);
    expect(data['status'], 'pending');
    expect(data.containsKey('withdrawn'), isFalse);
    expect(data.containsKey('baselineXP'), isFalse);
    expect(data['approvedAt'], isA<Timestamp?>());
  });
}
