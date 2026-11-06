import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/learning_time/learning_time_tracker.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_finish_service.dart';
import 'package:lerndex/src/features/rewards/data/reward_service.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';

const uid = 'parent1';
const cid = 'child1';

DocumentReference<Map<String, dynamic>> childRef(FakeFirebaseFirestore fs) =>
    fs.collection('users').doc(uid).collection('children').doc(cid);

void main() {
  group('Streak-Popup', () {
    test('nur wenn der Streak durch das Quiz auf einen Meilenstein wächst', () {
      expect(QuizFinishService.shouldShowStreakMilestone(2, 3), isTrue);
      expect(QuizFinishService.shouldShowStreakMilestone(6, 7), isTrue);
      // Zweites Quiz am selben Meilenstein-Tag: kein Popup mehr
      expect(QuizFinishService.shouldShowStreakMilestone(3, 3), isFalse);
      expect(QuizFinishService.shouldShowStreakMilestone(7, 7), isFalse);
      // Kein Meilenstein
      expect(QuizFinishService.shouldShowStreakMilestone(3, 4), isFalse);
      // Neustart nach Pause
      expect(QuizFinishService.shouldShowStreakMilestone(5, 1), isFalse);
    });
  });

  group('nextStreak', () {
    final now = DateTime(2026, 11, 5, 9);

    test('erster Lerntag → 1', () {
      expect(
        QuizFinishService.nextStreak(
          lastLearning: null,
          currentStreak: 0,
          now: now,
        ),
        1,
      );
    });

    test('heute schon gelernt → unverändert (mindestens 1)', () {
      final today = DateTime(2026, 11, 5, 7);
      expect(
        QuizFinishService.nextStreak(
          lastLearning: today,
          currentStreak: 4,
          now: now,
        ),
        4,
      );
      expect(
        QuizFinishService.nextStreak(
          lastLearning: today,
          currentStreak: 0,
          now: now,
        ),
        1,
      );
    });

    test('gestern gelernt → +1, auch kurz nach Mitternacht', () {
      expect(
        QuizFinishService.nextStreak(
          lastLearning: DateTime(2026, 11, 4, 23, 30),
          currentStreak: 2,
          now: DateTime(2026, 11, 5, 0, 15),
        ),
        3,
      );
    });

    test('über die Zeitumstellung im Frühjahr', () {
      expect(
        QuizFinishService.nextStreak(
          lastLearning: DateTime(2026, 3, 28, 20),
          currentStreak: 5,
          now: DateTime(2026, 3, 29, 9),
        ),
        6,
      );
    });

    test('Pause länger als ein Tag → 1', () {
      expect(
        QuizFinishService.nextStreak(
          lastLearning: DateTime(2026, 11, 2),
          currentStreak: 9,
          now: now,
        ),
        1,
      );
    });
  });

  group('QuizProgressWriter', () {
    late FakeFirebaseFirestore fs;
    final now = DateTime(2026, 11, 5, 10);

    setUp(() async {
      fs = FakeFirebaseFirestore();
      await childRef(fs).set({
        'name': 'Mia',
        'grade': 1,
        'age': 6,
        'xp': 50,
        'level': 1,
        'streak': 2,
        'lastLearningDate': Timestamp.fromDate(DateTime(2026, 11, 4, 18)),
        'totalQuizzes': 3,
        'perfectQuizzes': 1,
      });
    });

    test('schreibt XP, Streak, Quiz-Statistik und Lernzeit zusammen', () async {
      final tracker = LearningTimeTracker(
        userId: uid,
        childId: cid,
        subject: 'Zahlen',
        firestore: fs,
        clock: () => now,
        listenToApp: false,
      )..startTracking();
      for (var i = 0; i < 90; i++) {
        tracker.tick();
      }

      final progress = await QuizProgressWriter(fs, clock: () => now).write(
        userId: uid,
        childId: cid,
        earnedXP: 15,
        countQuiz: true,
        isPerfect: true,
        timeTracker: tracker,
      );
      tracker.dispose();

      expect(progress, isNotNull);
      expect(progress!.streakBefore, 2);
      expect(progress.newStreak, 3);

      final data = (await childRef(fs).get()).data()!;
      expect(data['xp'], 65);
      expect(data['level'], XPService.calculateLevelFromXP(65));
      expect(data['xpToNextLevel'], XPService.calculateXPToNextLevel(65, 2));
      expect(data['streak'], 3);
      expect(data['totalQuizzes'], 4);
      expect(data['perfectQuizzes'], 2);
      expect(data['totalLearningSeconds'], 90);
      expect(data['firstLearningDate'], isNotNull);
      expect(data['name'], 'Mia');

      final stats = (await childRef(
        fs,
      ).collection('learning_stats').doc('2026-11-05').get()).data()!;
      expect(stats['seconds'], 90);
      expect(stats['subjects'], {'Zahlen': 90});

      // Lokal berechnetes Kind passt zum gespeicherten Stand
      expect(progress.child.xp, 65);
      expect(progress.child.level, data['level']);
      expect(progress.child.streak, 3);
      expect(progress.child.totalQuizzes, 4);
      expect(tracker.trackedSeconds, 0);
    });

    test('Abbruch: nur XP und Lernzeit, kein Streak, kein Quiz', () async {
      await QuizProgressWriter(
        fs,
        clock: () => now,
      ).write(userId: uid, childId: cid, earnedXP: 6, countQuiz: false);
      final data = (await childRef(fs).get()).data()!;
      expect(data['xp'], 56);
      expect(data['streak'], 2);
      expect(data['totalQuizzes'], 3);
    });

    test('nichts zu tun → kein Schreibvorgang', () async {
      final result = await QuizProgressWriter(
        fs,
        clock: () => now,
      ).write(userId: uid, childId: cid, earnedXP: 0, countQuiz: false);
      expect(result, isNull);
    });

    test('fehlendes Kind → null, Lernzeit bleibt im Tracker', () async {
      final tracker = LearningTimeTracker(
        userId: uid,
        childId: 'gibtsnicht',
        firestore: fs,
        clock: () => now,
        listenToApp: false,
      )..startTracking();
      tracker.tick();
      tracker.tick();
      final result = await QuizProgressWriter(fs, clock: () => now).write(
        userId: uid,
        childId: 'gibtsnicht',
        earnedXP: 3,
        countQuiz: true,
        timeTracker: tracker,
      );
      expect(result, isNull);
      expect(tracker.trackedSeconds, 2);
      tracker.dispose();
    });
  });

  group('QuizFinishService.run', () {
    test('aktualisiert das Kind und prüft Belohnungen', () async {
      final fs = FakeFirebaseFirestore();
      await childRef(fs).set({'name': 'Mia', 'xp': 0, 'level': 1});
      ChildModel? updated;

      final result = await QuizFinishService.run(
        writer: QuizProgressWriter(fs),
        rewardService: RewardService(fs),
        onChildUpdated: (c) => updated = c,
        userId: uid,
        childId: cid,
        isPerfect: false,
        earnedXP: 9,
      );

      expect(result, isNotNull);
      expect(result!.newStreak, 1);
      expect(result.rewards, isEmpty);
      expect(updated?.xp, 9);
      expect(updated?.streak, 1);
    });
  });
}
