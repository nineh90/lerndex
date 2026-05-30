import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';

RewardModel reward({
  required RewardTrigger trigger,
  int? requiredLevel,
  int? requiredXP,
  int? requiredStars,
  int? requiredStreak,
  int? requiredQuizCount,
  int? baselineXP,
  RewardStatus status = RewardStatus.pending,
}) {
  return RewardModel(
    id: 'r1',
    childId: 'c1',
    title: 'Belohnung',
    description: 'Beschreibung',
    type: RewardType.system,
    trigger: trigger,
    requiredLevel: requiredLevel,
    requiredXP: requiredXP,
    requiredStars: requiredStars,
    requiredStreak: requiredStreak,
    requiredQuizCount: requiredQuizCount,
    baselineXP: baselineXP,
    status: status,
    reward: 'Eis',
    createdAt: DateTime(2026, 1, 1),
    createdBy: 'system',
  );
}

void main() {
  group('isTriggeredBy – Level', () {
    final r = reward(trigger: RewardTrigger.level, requiredLevel: 5);
    test('erfüllt ab erreichtem Level', () {
      expect(
        r.isTriggeredBy(
          currentLevel: 5,
          currentXP: 0,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 0,
        ),
        isTrue,
      );
    });
    test('nicht erfüllt darunter', () {
      expect(
        r.isTriggeredBy(
          currentLevel: 4,
          currentXP: 0,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 0,
        ),
        isFalse,
      );
    });
  });

  group('isTriggeredBy – XP mit Baseline', () {
    test('Ziel = baselineXP + requiredXP', () {
      final r = reward(
        trigger: RewardTrigger.xp,
        requiredXP: 100,
        baselineXP: 50,
      );
      expect(
        r.isTriggeredBy(
          currentLevel: 1,
          currentXP: 149,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 0,
        ),
        isFalse,
      );
      expect(
        r.isTriggeredBy(
          currentLevel: 1,
          currentXP: 150,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 0,
        ),
        isTrue,
      );
    });

    test('ohne Baseline zählt absolute XP', () {
      final r = reward(trigger: RewardTrigger.xp, requiredXP: 100);
      expect(
        r.isTriggeredBy(
          currentLevel: 1,
          currentXP: 100,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 0,
        ),
        isTrue,
      );
    });
  });

  group('isTriggeredBy – Streak / QuizCount / PerfectQuiz', () {
    test('Streak', () {
      final r = reward(trigger: RewardTrigger.streak, requiredStreak: 7);
      expect(
        r.isTriggeredBy(
          currentLevel: 1,
          currentXP: 0,
          currentStars: 0,
          currentStreak: 7,
          currentQuizCount: 0,
        ),
        isTrue,
      );
    });

    test('QuizCount', () {
      final r = reward(trigger: RewardTrigger.quizCount, requiredQuizCount: 10);
      expect(
        r.isTriggeredBy(
          currentLevel: 1,
          currentXP: 0,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 9,
        ),
        isFalse,
      );
    });

    test('PerfectQuiz folgt dem Flag', () {
      final r = reward(trigger: RewardTrigger.perfectQuiz);
      expect(
        r.isTriggeredBy(
          currentLevel: 1,
          currentXP: 0,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 0,
          isPerfectQuiz: true,
        ),
        isTrue,
      );
      expect(
        r.isTriggeredBy(
          currentLevel: 1,
          currentXP: 0,
          currentStars: 0,
          currentStreak: 0,
          currentQuizCount: 0,
          isPerfectQuiz: false,
        ),
        isFalse,
      );
    });
  });

  group('isTriggeredBy – manuelle Trigger lösen nie automatisch aus', () {
    test('manual', () {
      final r = reward(trigger: RewardTrigger.manual);
      expect(
        r.isTriggeredBy(
          currentLevel: 99,
          currentXP: 99999,
          currentStars: 999,
          currentStreak: 999,
          currentQuizCount: 999,
          isPerfectQuiz: true,
        ),
        isFalse,
      );
    });
    test('avatarUnlock', () {
      final r = reward(trigger: RewardTrigger.avatarUnlock);
      expect(
        r.isTriggeredBy(
          currentLevel: 99,
          currentXP: 99999,
          currentStars: 999,
          currentStreak: 999,
          currentQuizCount: 999,
        ),
        isFalse,
      );
    });
  });

  group('canClaim', () {
    test('nur bei Status approved', () {
      expect(reward(trigger: RewardTrigger.manual, status: RewardStatus.approved)
          .canClaim, isTrue);
      expect(reward(trigger: RewardTrigger.manual, status: RewardStatus.pending)
          .canClaim, isFalse);
      expect(reward(trigger: RewardTrigger.manual, status: RewardStatus.claimed)
          .canClaim, isFalse);
    });
  });

  group('conditionText', () {
    test('zeigt passende Bedingung je Trigger', () {
      expect(reward(trigger: RewardTrigger.level, requiredLevel: 5).conditionText,
          contains('Level 5'));
      expect(reward(trigger: RewardTrigger.streak, requiredStreak: 7)
          .conditionText, contains('7 Tage'));
      expect(reward(trigger: RewardTrigger.perfectQuiz).conditionText,
          contains('Perfektes Quiz'));
    });
  });

  group('Firestore Roundtrip', () {
    test('fromFirestore(toFirestore()) erhält Kernfelder', () {
      final original = reward(
        trigger: RewardTrigger.streak,
        requiredStreak: 7,
        status: RewardStatus.approved,
      );
      final map = original.toFirestore();
      // createdAt ist im toFirestore ein echter Timestamp
      expect(map['createdAt'], isA<Timestamp>());
      final restored = RewardModel.fromFirestore(map, 'r1');
      expect(restored.trigger, RewardTrigger.streak);
      expect(restored.requiredStreak, 7);
      expect(restored.status, RewardStatus.approved);
      expect(restored.type, RewardType.system);
      expect(restored.reward, 'Eis');
    });
  });
}
