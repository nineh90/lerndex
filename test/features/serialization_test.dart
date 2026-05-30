import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';
import 'package:lerndex/src/features/rewards/domain/reward_enums.dart';
import 'package:lerndex/src/features/rewards/domain/reward_model.dart';

void main() {
  group('RewardModel.toFirestore', () {
    test('serialisiert optionale Felder wenn gesetzt', () {
      final r = RewardModel(
        id: 'r1',
        childId: 'c1',
        title: 'XP-Ziel',
        description: 'Sammle XP',
        type: RewardType.parent,
        trigger: RewardTrigger.xp,
        requiredXP: 100,
        baselineXP: 50,
        avatarUnlockId: 'avatar-rare',
        bonusXP: 20,
        status: RewardStatus.approved,
        reward: 'Kinobesuch',
        createdAt: DateTime(2026, 3, 1, 12),
        approvedAt: DateTime(2026, 3, 2, 9),
        createdBy: 'parent1',
        parentSeen: true,
      );
      final map = r.toFirestore();
      expect(map['type'], 'parent');
      expect(map['trigger'], 'xp');
      expect(map['baselineXP'], 50);
      expect(map['avatarUnlockId'], 'avatar-rare');
      expect(map['bonusXP'], 20);
      expect(map['parentSeen'], isTrue);
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['approvedAt'], isA<Timestamp>());
    });

    test('lässt optionale Felder weg wenn null', () {
      final r = RewardModel(
        id: 'r1',
        childId: 'c1',
        title: 't',
        description: 'd',
        type: RewardType.system,
        trigger: RewardTrigger.level,
        requiredLevel: 5,
        status: RewardStatus.pending,
        reward: 'x',
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'system',
      );
      final map = r.toFirestore();
      expect(map.containsKey('baselineXP'), isFalse);
      expect(map.containsKey('avatarUnlockId'), isFalse);
      expect(map.containsKey('bonusXP'), isFalse);
      expect(map['approvedAt'], isNull);
      expect(map['claimedAt'], isNull);
    });
  });

  group('RewardModel.fromFirestore', () {
    test('liest ein vollständiges Dokument inkl. Timestamps', () {
      final created = DateTime(2026, 2, 1, 8);
      final approved = DateTime(2026, 2, 2, 8);
      final claimed = DateTime(2026, 2, 3, 8);
      final r = RewardModel.fromFirestore({
        'childId': 'c9',
        'title': 'Titel',
        'description': 'Beschr',
        'type': 'parent',
        'trigger': 'streak',
        'requiredStreak': 7,
        'baselineXP': 10,
        'avatarUnlockId': 'a1',
        'bonusXP': 5,
        'status': 'claimed',
        'reward': 'Belohnung',
        'createdAt': Timestamp.fromDate(created),
        'approvedAt': Timestamp.fromDate(approved),
        'claimedAt': Timestamp.fromDate(claimed),
        'createdBy': 'parent9',
        'parentSeen': true,
      }, 'docId');
      expect(r.id, 'docId');
      expect(r.childId, 'c9');
      expect(r.type, RewardType.parent);
      expect(r.trigger, RewardTrigger.streak);
      expect(r.requiredStreak, 7);
      expect(r.bonusXP, 5);
      expect(r.status, RewardStatus.claimed);
      expect(r.createdAt, created);
      expect(r.approvedAt, approved);
      expect(r.claimedAt, claimed);
      expect(r.parentSeen, isTrue);
    });

    test('nutzt Defaults bei leerem Dokument', () {
      final r = RewardModel.fromFirestore({}, 'id');
      expect(r.childId, '');
      expect(r.type, RewardType.parent);
      expect(r.trigger, RewardTrigger.manual);
      expect(r.status, RewardStatus.pending);
      expect(r.createdBy, 'system');
      expect(r.parentSeen, isFalse);
    });
  });

  group('RewardModel.copyWith', () {
    test('ändert nur angegebene Felder', () {
      final base = RewardModel(
        id: 'r1',
        childId: 'c1',
        title: 'alt',
        description: 'd',
        type: RewardType.system,
        trigger: RewardTrigger.level,
        requiredLevel: 5,
        status: RewardStatus.pending,
        reward: 'x',
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'system',
      );
      final updated = base.copyWith(
        status: RewardStatus.approved,
        title: 'neu',
      );
      expect(updated.status, RewardStatus.approved);
      expect(updated.title, 'neu');
      expect(updated.requiredLevel, 5); // unverändert
      expect(updated.childId, 'c1');
    });
  });

  group('GeneratedQuestion.toFirestore', () {
    test('serialisiert Inhalt und Status', () {
      final q = GeneratedQuestion(
        id: 'q1',
        question: 'Was ist 2+2?',
        options: const ['3', '4'],
        correctAnswer: '4',
        solution: 'Addition',
        difficulty: 'easy',
        topic: 'Addition',
        status: TaskApprovalStatus.approved,
        createdAt: DateTime(2026, 1, 1),
        approvedAt: DateTime(2026, 1, 2),
        approvedBy: 'parent1',
      );
      final map = q.toFirestore();
      expect(map['question'], 'Was ist 2+2?');
      expect(map['correctAnswer'], '4');
      expect(map['options'], ['3', '4']);
      expect(map['status'], 'approved');
      expect(map['solution'], 'Addition');
      expect(map['approvedBy'], 'parent1');
      expect(map['approvedAt'], isA<Timestamp>());
    });
  });
}
