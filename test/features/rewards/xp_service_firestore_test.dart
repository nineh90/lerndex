import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';

// Tests gegen einen In-Memory-Firestore (fake_cloud_firestore). Deckt die
// Firestore-gekoppelte XP-/Streak-Logik ab, die in der Vergangenheit
// XP-Berechnungsfehler hatte.

const uid = 'parent1';
const cid = 'child1';

DocumentReference<Map<String, dynamic>> childRef(FakeFirebaseFirestore fs) =>
    fs.collection('users').doc(uid).collection('children').doc(cid);

Future<void> seedChild(
  FakeFirebaseFirestore fs,
  Map<String, dynamic> data,
) async {
  await childRef(fs).set(data);
}

void main() {
  group('addXP', () {
    test('vergibt XP und berechnet Level + xpToNextLevel korrekt', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'xp': 0, 'level': 1});
      final service = XPService(fs);

      final result =
          await service.addXP(userId: uid, childId: cid, xpToAdd: 60);

      expect(result.newXP, 60);
      expect(result.newLevel, 2); // 60 XP = exakte Schwelle für Level 2
      expect(result.leveledUp, isTrue);
      expect(result.xpGained, 60);
      expect(result.xpToNextLevel, XPService.calculateXPForLevel(2));

      // Persistenz prüfen
      final stored = (await childRef(fs).get()).data()!;
      expect(stored['xp'], 60);
      expect(stored['level'], 2);
      expect(stored['xpToNextLevel'], XPService.calculateXPForLevel(2));
    });

    test('kein Level-Up unterhalb der Schwelle', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'xp': 0, 'level': 1});
      final service = XPService(fs);

      final result =
          await service.addXP(userId: uid, childId: cid, xpToAdd: 10);

      expect(result.newXP, 10);
      expect(result.newLevel, 1);
      expect(result.leveledUp, isFalse);
      expect(result.xpToNextLevel, 50); // 60 - 10
    });

    test('XP akkumuliert über mehrere Aufrufe', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'xp': 0, 'level': 1});
      final service = XPService(fs);

      await service.addXP(userId: uid, childId: cid, xpToAdd: 30);
      final result =
          await service.addXP(userId: uid, childId: cid, xpToAdd: 30);

      expect(result.newXP, 60);
      expect(result.newLevel, 2);
      // Stored level muss zur berechneten XP passen (Regressionsschutz)
      final stored = (await childRef(fs).get()).data()!;
      expect(stored['level'], XPService.calculateLevelFromXP(stored['xp']));
    });

    test('wirft wenn Kind nicht existiert', () async {
      final fs = FakeFirebaseFirestore();
      final service = XPService(fs);
      expect(
        () => service.addXP(userId: uid, childId: 'missing', xpToAdd: 5),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('addTutorXP – globales Tageslimit', () {
    test('Guard: dailyXpSoFar >= maxXpPerDay → null', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'xp': 0, 'level': 1});
      final service = XPService(fs);

      final result = await service.addTutorXP(
        userId: uid,
        childId: cid,
        dailyXpSoFar: 50,
      );
      expect(result, isNull);
    });

    test('vergibt Standard-XP und setzt Tageszähler', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'xp': 0, 'level': 1});
      final service = XPService(fs);

      final result = await service.addTutorXP(
        userId: uid,
        childId: cid,
        dailyXpSoFar: 0,
      );

      expect(result, isNotNull);
      expect(result!.xpGained, 2);
      final stored = (await childRef(fs).get()).data()!;
      expect(stored['tutorXpToday'], 2);
      expect(stored['tutorXpLastDate'], isA<Timestamp>());
    });

    test('deckelt auf verbleibende Tages-XP', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'xp': 0,
        'level': 1,
        'tutorXpToday': 49,
        'tutorXpLastDate': Timestamp.fromDate(DateTime.now()),
      });
      final service = XPService(fs);

      final result = await service.addTutorXP(
        userId: uid,
        childId: cid,
        dailyXpSoFar: 49,
      );

      expect(result, isNotNull);
      expect(result!.xpGained, 1); // nur noch 1 XP bis 50
    });

    test('in-Transaktion-Limit: doc-Zähler bereits am Maximum → null', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'xp': 0,
        'level': 1,
        'tutorXpToday': 50,
        'tutorXpLastDate': Timestamp.fromDate(DateTime.now()),
      });
      final service = XPService(fs);

      // dailyXpSoFar absichtlich 0 → Guard greift nicht, aber doc-Zähler = 50
      final result = await service.addTutorXP(
        userId: uid,
        childId: cid,
        dailyXpSoFar: 0,
      );
      expect(result, isNull);
    });

    test('Tageswechsel setzt den Zähler zurück', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'xp': 0,
        'level': 1,
        'tutorXpToday': 50,
        'tutorXpLastDate':
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
      });
      final service = XPService(fs);

      final result = await service.addTutorXP(
        userId: uid,
        childId: cid,
        dailyXpSoFar: 0,
      );

      expect(result, isNotNull);
      expect(result!.xpGained, 2); // neuer Tag → wieder voll verfügbar
      final stored = (await childRef(fs).get()).data()!;
      expect(stored['tutorXpToday'], 2);
    });
  });

  group('getTutorXpToday', () {
    test('liefert gespeicherten Wert am selben Tag', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'tutorXpToday': 12,
        'tutorXpLastDate': Timestamp.fromDate(DateTime.now()),
      });
      final service = XPService(fs);
      expect(await service.getTutorXpToday(userId: uid, childId: cid), 12);
    });

    test('0 an einem anderen Tag', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'tutorXpToday': 12,
        'tutorXpLastDate':
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 2))),
      });
      final service = XPService(fs);
      expect(await service.getTutorXpToday(userId: uid, childId: cid), 0);
    });

    test('0 wenn Kind fehlt', () async {
      final fs = FakeFirebaseFirestore();
      final service = XPService(fs);
      expect(await service.getTutorXpToday(userId: uid, childId: 'x'), 0);
    });
  });

  group('updateStreak', () {
    test('erster Lerntag → Streak 1', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'xp': 0, 'level': 1});
      final service = XPService(fs);
      expect(await service.updateStreak(userId: uid, childId: cid), 1);
    });

    test('gestern gelernt → Streak +1', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'streak': 3,
        'lastLearningDate':
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
      });
      final service = XPService(fs);
      expect(await service.updateStreak(userId: uid, childId: cid), 4);
    });

    test('Mitternachts-Fall: gestern 23:00, jetzt früh → zählt als gestern',
        () async {
      final fs = FakeFirebaseFirestore();
      final now = DateTime.now();
      final yesterdayLate =
          DateTime(now.year, now.month, now.day).subtract(const Duration(hours: 1));
      await seedChild(fs, {
        'streak': 2,
        'lastLearningDate': Timestamp.fromDate(yesterdayLate),
      });
      final service = XPService(fs);
      expect(await service.updateStreak(userId: uid, childId: cid), 3);
    });

    test('heute bereits gelernt → Streak unverändert', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'streak': 5,
        'lastLearningDate': Timestamp.fromDate(DateTime.now()),
      });
      final service = XPService(fs);
      expect(await service.updateStreak(userId: uid, childId: cid), 5);
    });

    test('Legacy-Korrektur: streak 0 obwohl heute gelernt → 1', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'streak': 0,
        'lastLearningDate': Timestamp.fromDate(DateTime.now()),
      });
      final service = XPService(fs);
      expect(await service.updateStreak(userId: uid, childId: cid), 1);
    });

    test('Pause > 1 Tag → Reset auf 1', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'streak': 9,
        'lastLearningDate':
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 3))),
      });
      final service = XPService(fs);
      expect(await service.updateStreak(userId: uid, childId: cid), 1);
    });
  });

  group('checkAndResetStreakIfExpired', () {
    test('kein Lerndatum → unverändert (0)', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'streak': 0});
      final service = XPService(fs);
      expect(
        await service.checkAndResetStreakIfExpired(userId: uid, childId: cid),
        0,
      );
    });

    test('gestern gelernt → Streak bleibt aktiv', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'streak': 5,
        'lastLearningDate':
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
      });
      final service = XPService(fs);
      expect(
        await service.checkAndResetStreakIfExpired(userId: uid, childId: cid),
        5,
      );
    });

    test('Pause > 1 Tag → Reset auf 0 und persistiert', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {
        'streak': 5,
        'lastLearningDate':
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 4))),
      });
      final service = XPService(fs);
      expect(
        await service.checkAndResetStreakIfExpired(userId: uid, childId: cid),
        0,
      );
      final stored = (await childRef(fs).get()).data()!;
      expect(stored['streak'], 0);
    });
  });

  group('updateQuizStats', () {
    test('erhöht totalQuizzes und perfectQuizzes bei perfektem Quiz', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'totalQuizzes': 2, 'perfectQuizzes': 1});
      final service = XPService(fs);

      await service.updateQuizStats(userId: uid, childId: cid, isPerfect: true);

      final stored = (await childRef(fs).get()).data()!;
      expect(stored['totalQuizzes'], 3);
      expect(stored['perfectQuizzes'], 2);
    });

    test('erhöht nur totalQuizzes bei nicht-perfektem Quiz', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'totalQuizzes': 2, 'perfectQuizzes': 1});
      final service = XPService(fs);

      await service.updateQuizStats(userId: uid, childId: cid, isPerfect: false);

      final stored = (await childRef(fs).get()).data()!;
      expect(stored['totalQuizzes'], 3);
      expect(stored['perfectQuizzes'], 1);
    });
  });

  group('getChild', () {
    test('liefert ChildModel mit korrekter ID', () async {
      final fs = FakeFirebaseFirestore();
      await seedChild(fs, {'name': 'Mia', 'xp': 42, 'level': 2, 'grade': 3});
      final service = XPService(fs);

      final child = await service.getChild(userId: uid, childId: cid);
      expect(child, isNotNull);
      expect(child!.id, cid);
      expect(child.name, 'Mia');
      expect(child.xp, 42);
    });

    test('null wenn Kind fehlt', () async {
      final fs = FakeFirebaseFirestore();
      final service = XPService(fs);
      expect(await service.getChild(userId: uid, childId: 'x'), isNull);
    });
  });
}
