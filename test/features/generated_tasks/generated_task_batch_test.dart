import 'package:flutter_test/flutter_test.dart';
// generated_task_models re-exportiert generated_task_batch.
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';

GeneratedTaskBatch batch({
  int total = 10,
  int approved = 0,
  int pending = 10,
  int rejected = 0,
}) {
  return GeneratedTaskBatch(
    id: 'b1',
    childId: 'c1',
    childName: 'Max',
    subject: Subject.mathe,
    imageUrl: 'http://example.com/img.jpg',
    createdAt: DateTime(2026, 1, 1),
    totalTasks: total,
    approvedTasks: approved,
    pendingTasks: pending,
    rejectedTasks: rejected,
    questions: const [],
  );
}

void main() {
  group('isFullyReviewed', () {
    test('true wenn keine ausstehenden Aufgaben', () {
      expect(batch(pending: 0, approved: 7, rejected: 3).isFullyReviewed,
          isTrue);
    });
    test('false bei offenen Aufgaben', () {
      expect(batch(pending: 4).isFullyReviewed, isFalse);
    });
  });

  group('hasApprovedTasks', () {
    test('true wenn mindestens eine freigegeben', () {
      expect(batch(approved: 1).hasApprovedTasks, isTrue);
    });
    test('false ohne Freigaben', () {
      expect(batch(approved: 0).hasApprovedTasks, isFalse);
    });
  });

  group('reviewProgress', () {
    test('0 bei totalTasks == 0', () {
      expect(batch(total: 0, pending: 0).reviewProgress, 0);
    });
    test('Prozentsatz aus approved + rejected', () {
      // 4 von 10 bearbeitet → 40 %
      expect(
        batch(total: 10, approved: 3, rejected: 1, pending: 6).reviewProgress,
        closeTo(40.0, 0.0001),
      );
    });
    test('100 % wenn alles bearbeitet', () {
      expect(
        batch(total: 4, approved: 2, rejected: 2, pending: 0).reviewProgress,
        closeTo(100.0, 0.0001),
      );
    });
  });

  group('toFirestore', () {
    test('enthält Subject als value-String', () {
      final map = batch().toFirestore();
      expect(map['subject'], 'mathe');
      expect(map['childName'], 'Max');
      expect(map['totalTasks'], 10);
    });
  });
}
