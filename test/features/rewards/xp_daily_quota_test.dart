import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';
import 'package:lerndex/src/features/rewards/domain/xp_result.dart';

// Tageslimits fürs Malspiel: XP pro Tag und KI-Prüfungen pro Tag.

const uid = 'parent1';
const cid = 'child1';

DocumentReference<Map<String, dynamic>> childRef(FakeFirebaseFirestore fs) =>
    fs.collection('users').doc(uid).collection('children').doc(cid);

void main() {
  late FakeFirebaseFirestore fs;
  late XPService service;

  setUp(() async {
    fs = FakeFirebaseFirestore();
    service = XPService(fs);
    await childRef(fs).set({'xp': 0, 'level': 1});
  });

  Future<XPResult?> addTracingXP() => service.addDailyCappedXP(
    userId: uid,
    childId: cid,
    xpToAdd: 10,
    counterField: 'tracingXpToday',
    dateField: 'tracingXpLastDate',
    maxXpPerDay: 25,
  );

  test('XP bis zum Tageslimit, danach keine mehr', () async {
    expect((await addTracingXP())?.xpGained, 10);
    expect((await addTracingXP())?.xpGained, 10);
    expect((await addTracingXP())?.xpGained, 5); // Rest bis 25
    expect(await addTracingXP(), isNull);

    final data = (await childRef(fs).get()).data()!;
    expect(data['xp'], 25);
    expect(data['tracingXpToday'], 25);
  });

  test('neuer Tag: Zähler beginnt wieder bei 0', () async {
    await childRef(fs).update({
      'tracingXpToday': 25,
      'tracingXpLastDate': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
    });

    expect((await addTracingXP())?.xpGained, 10);
    expect((await childRef(fs).get()).data()!['tracingXpToday'], 10);
  });

  test('KI-Prüfungen: höchstens maxPerDay am Tag', () async {
    Future<bool> reserve() => service.reserveDailyQuota(
      userId: uid,
      childId: cid,
      counterField: 'tracingChecksToday',
      dateField: 'tracingChecksLastDate',
      maxPerDay: 2,
    );

    expect(await reserve(), isTrue);
    expect(await reserve(), isTrue);
    expect(await reserve(), isFalse);
    expect((await childRef(fs).get()).data()!['tracingChecksToday'], 2);
  });
}
