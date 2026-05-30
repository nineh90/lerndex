import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';

void main() {
  group('RewardStatus Roundtrip', () {
    test('fromFirestore(toFirestore(x)) == x', () {
      for (final status in RewardStatus.values) {
        expect(
          RewardStatusExtension.fromFirestore(status.toFirestore()),
          status,
        );
      }
    });
    test('unbekannter Wert → pending', () {
      expect(RewardStatusExtension.fromFirestore('xxx'), RewardStatus.pending);
    });
  });

  group('RewardType Roundtrip', () {
    test('fromFirestore(toFirestore(x)) == x', () {
      for (final type in RewardType.values) {
        expect(RewardTypeExtension.fromFirestore(type.toFirestore()), type);
      }
    });
    test('unbekannter Wert → parent', () {
      expect(RewardTypeExtension.fromFirestore('xxx'), RewardType.parent);
    });
  });

  group('RewardTrigger Roundtrip', () {
    test('fromFirestore(toFirestore(x)) == x für alle Trigger', () {
      for (final trigger in RewardTrigger.values) {
        expect(
          RewardTriggerExtension.fromFirestore(trigger.toFirestore()),
          trigger,
          reason: 'Trigger $trigger muss roundtrip-fähig sein',
        );
      }
    });

    test('snake_case Mapping ist korrekt', () {
      expect(RewardTrigger.perfectQuiz.toFirestore(), 'perfect_quiz');
      expect(RewardTrigger.quizCount.toFirestore(), 'quiz_count');
      expect(RewardTrigger.avatarUnlock.toFirestore(), 'avatar_unlock');
    });

    test('unbekannter Wert → manual', () {
      expect(
        RewardTriggerExtension.fromFirestore('unbekannt'),
        RewardTrigger.manual,
      );
    });

    test('jeder Trigger hat einen displayName', () {
      for (final trigger in RewardTrigger.values) {
        expect(trigger.displayName, isNotEmpty);
      }
    });
  });
}
