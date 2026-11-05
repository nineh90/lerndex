import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/learning_time/learning_time_tracker.dart';

const uid = 'parent1';
const cid = 'child1';

DocumentReference<Map<String, dynamic>> childRef(FakeFirebaseFirestore fs) =>
    fs.collection('users').doc(uid).collection('children').doc(cid);

void main() {
  late FakeFirebaseFirestore fs;
  late DateTime now;

  LearningTimeTracker tracker({String? subject = 'Zahlen'}) =>
      LearningTimeTracker(
        userId: uid,
        childId: cid,
        subject: subject,
        firestore: fs,
        clock: () => now,
        listenToApp: false,
      );

  void seconds(LearningTimeTracker t, int n) {
    for (var i = 0; i < n; i++) {
      now = now.add(const Duration(seconds: 1));
      t.tick();
    }
  }

  setUp(() async {
    fs = FakeFirebaseFirestore();
    now = DateTime(2026, 11, 5, 10);
    await childRef(fs).set({'name': 'Mia', 'xp': 0});
  });

  group('Zählen', () {
    test('zählt jede Sekunde, solange das Kind aktiv ist', () {
      final t = tracker()..startTracking();
      seconds(t, 30);
      expect(t.trackedSeconds, 30);
      t.dispose();
    });

    test(
      'hört nach 3 Minuten ohne Eingabe auf und zählt nach Tippen weiter',
      () {
        final t = tracker()..startTracking();
        seconds(t, 300); // 5 Minuten ohne Eingabe
        expect(t.isIdle, isTrue);
        expect(t.trackedSeconds, LearningTimeTracker.idleTimeout.inSeconds - 1);

        t.markActivity();
        final before = t.trackedSeconds;
        seconds(t, 10);
        expect(t.trackedSeconds, before + 10);
        t.dispose();
      },
    );

    test('zählt im Hintergrund nicht', () {
      final t = tracker()..startTracking();
      seconds(t, 5);
      t.didChangeAppLifecycleState(AppLifecycleState.paused);
      seconds(t, 60);
      t.didChangeAppLifecycleState(AppLifecycleState.hidden);
      seconds(t, 60);
      expect(t.isCounting, isFalse);

      t.didChangeAppLifecycleState(AppLifecycleState.resumed);
      seconds(t, 5);
      // Die 5 Sekunden vor dem Wechsel wurden beim Pausieren gespeichert.
      expect(t.trackedSeconds, 5);
      t.dispose();
    });

    test('inactive (z.B. Benachrichtigungen) pausiert nicht', () {
      final t = tracker()..startTracking();
      t.didChangeAppLifecycleState(AppLifecycleState.inactive);
      seconds(t, 5);
      expect(t.trackedSeconds, 5);
      t.dispose();
    });
  });

  group('saveTime', () {
    test('schreibt Kind und Tages-Statistik ohne Transaktion', () async {
      final t = tracker()..startTracking();
      seconds(t, 42);
      t.stopTracking();
      await t.saveTime();

      final child = (await childRef(fs).get()).data()!;
      expect(child['totalLearningSeconds'], 42);
      expect(child['firstLearningDate'], isNotNull);
      expect(child.containsKey('lastLearningDate'), isFalse);

      final stats = (await childRef(
        fs,
      ).collection('learning_stats').doc('2026-11-05').get()).data()!;
      expect(stats['seconds'], 42);
      expect(stats['subjects'], {'Zahlen': 42});
      expect(t.trackedSeconds, 0);
    });

    test(
      'Fächer desselben Tages werden zusammengeführt, nicht überschrieben',
      () async {
        final math = tracker()..startTracking();
        seconds(math, 10);
        await math.saveTime();

        final letters = tracker(subject: 'Farben & Formen')..startTracking();
        seconds(letters, 20);
        await letters.saveTime();

        seconds(math, 5);
        await math.saveTime();

        final stats = (await childRef(
          fs,
        ).collection('learning_stats').doc('2026-11-05').get()).data()!;
        expect(stats['seconds'], 35);
        expect(stats['subjects'], {'Zahlen': 15, 'Farben & Formen': 20});
        expect((await childRef(fs).get()).data()!['totalLearningSeconds'], 35);
        math.dispose();
        letters.dispose();
      },
    );

    test(
      'firstLearningDate bleibt beim zweiten Speichern unverändert',
      () async {
        final first = Timestamp.fromDate(DateTime(2026, 1, 1));
        await childRef(fs).update({'firstLearningDate': first});
        final t = tracker()..startTracking();
        seconds(t, 3);
        await t.saveTime();
        expect((await childRef(fs).get()).data()!['firstLearningDate'], first);
        t.dispose();
      },
    );

    test('ohne gezählte Sekunden wird nichts geschrieben', () async {
      final t = tracker();
      await t.saveTime();
      final stats = await childRef(fs).collection('learning_stats').get();
      expect(stats.docs, isEmpty);
    });
  });
}
