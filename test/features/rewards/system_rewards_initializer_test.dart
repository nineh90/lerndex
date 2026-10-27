import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/data/system_rewards_initializer.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SystemRewardsInitializer initializer;

  CollectionReference<Map<String, dynamic>> rewards() => db
      .collection('users')
      .doc('u1')
      .collection('children')
      .doc('c1')
      .collection('rewards');

  setUp(() {
    db = FakeFirebaseFirestore();
    initializer = SystemRewardsInitializer(db);
  });

  test('neue Kinder bekommen die neutralen Titel', () async {
    await initializer.initializeSystemRewards(userId: 'u1', childId: 'c1');

    final titles = (await rewards().get()).docs
        .map((d) => d['title'] as String)
        .toList();
    expect(titles, contains('💪 Fleißig gelernt!'));
    expect(titles, contains('🔥 Super gelernt!'));
    expect(titles.where((t) => t.contains('Lernerin')), isEmpty);
  });

  test('alte Titel werden umbenannt, ohne doppelte Belohnung', () async {
    await initializer.initializeSystemRewards(userId: 'u1', childId: 'c1');
    final before = await rewards().get();

    // Stand vor der Umbenennung nachstellen; eine davon schon eingelöst
    for (final doc in before.docs) {
      if (doc['title'] == '💪 Fleißig gelernt!') {
        await doc.reference.update({
          'title': '💪 Fleißige Lernerin!',
          'status': 'claimed',
        });
      } else if (doc['title'] == '🔥 Super gelernt!') {
        await doc.reference.update({'title': '🔥 Super Lernerin!'});
      }
    }

    await initializer.addMissingSystemRewards(userId: 'u1', childId: 'c1');

    final after = await rewards().get();
    expect(after.docs.length, before.docs.length);
    final fleissig = after.docs.where(
      (d) => d['title'] == '💪 Fleißig gelernt!',
    );
    expect(fleissig, hasLength(1));
    expect(fleissig.single['status'], 'claimed');
    expect(
      after.docs.where((d) => d['title'] == '🔥 Super gelernt!'),
      hasLength(1),
    );
    expect(
      after.docs.where((d) => (d['title'] as String).contains('Lernerin')),
      isEmpty,
    );
  });
}
