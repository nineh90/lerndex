import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';
import 'package:lerndex/src/features/subscription/data/subscription_model.dart';

// Bündelt die UI-Label-/Anzeige-Logik (switch-Zweige), damit alle Enum-Fälle
// abgedeckt sind und keine Variante einen leeren/falschen Text liefert.

RewardModel rewardWith(RewardTrigger trigger, RewardStatus status) {
  return RewardModel(
    id: 'r',
    childId: 'c',
    title: 't',
    description: 'd',
    type: RewardType.system,
    trigger: trigger,
    requiredLevel: 3,
    requiredXP: 100,
    requiredStars: 5,
    requiredStreak: 7,
    requiredQuizCount: 10,
    status: status,
    reward: 'Eis',
    createdAt: DateTime(2026, 1, 1),
    createdBy: 'system',
  );
}

void main() {
  group('SubscriptionPlan Labels', () {
    test('jeder Plan hat displayName und priceLabel', () {
      for (final plan in SubscriptionPlan.values) {
        expect(plan.displayName, isNotEmpty, reason: '$plan displayName');
        expect(plan.priceLabel, isNotEmpty, reason: '$plan priceLabel');
      }
    });
    test('konkrete Werte stimmen', () {
      expect(SubscriptionPlan.solo.displayName, 'Solo');
      expect(SubscriptionPlan.family.priceLabel, '39,99 € / Monat');
      expect(SubscriptionPlan.none.priceLabel, 'Kostenlos');
    });
  });

  group('RewardModel.conditionText – alle Trigger', () {
    test('liefert für jeden Trigger einen Text', () {
      for (final trigger in RewardTrigger.values) {
        final text = rewardWith(trigger, RewardStatus.pending).conditionText;
        expect(text, isNotEmpty, reason: '$trigger conditionText');
      }
    });
    test('konkrete Beispiele', () {
      expect(rewardWith(RewardTrigger.xp, RewardStatus.pending).conditionText,
          contains('100 XP'));
      expect(rewardWith(RewardTrigger.quizCount, RewardStatus.pending)
          .conditionText, contains('10'));
      expect(rewardWith(RewardTrigger.manual, RewardStatus.pending)
          .conditionText, contains('Eltern'));
    });
  });

  group('RewardModel.statusEmoji – alle Status', () {
    test('jeder Status hat ein Emoji', () {
      for (final status in RewardStatus.values) {
        expect(rewardWith(RewardTrigger.level, status).statusEmoji,
            isNotEmpty);
      }
    });
    test('konkrete Zuordnung', () {
      expect(rewardWith(RewardTrigger.level, RewardStatus.pending).statusEmoji,
          '⏳');
      expect(rewardWith(RewardTrigger.level, RewardStatus.approved).statusEmoji,
          '🎁');
      expect(rewardWith(RewardTrigger.level, RewardStatus.claimed).statusEmoji,
          '✅');
    });
  });

  group('Subject.displayName – alle Fächer', () {
    test('jedes Fach hat einen Anzeigenamen', () {
      for (final subject in Subject.values) {
        expect(subject.displayName, isNotEmpty, reason: '$subject');
        expect(subject.value, isNotEmpty);
      }
    });
  });

  group('TaskApprovalStatus.displayName – alle Status', () {
    test('jeder Status hat einen Anzeigenamen', () {
      for (final status in TaskApprovalStatus.values) {
        expect(status.displayName, isNotEmpty);
      }
      expect(TaskApprovalStatus.pending.displayName, 'Ausstehend');
      expect(TaskApprovalStatus.rejected.displayName, 'Abgelehnt');
    });
  });
}
