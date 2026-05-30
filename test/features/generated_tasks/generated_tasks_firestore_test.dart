import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
// generated_task_models re-exportiert generated_task_batch (GeneratedTaskBatch).
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';

void main() {
  group('GeneratedQuestion.fromFirestore', () {
    test('liest ein Dokument inkl. Status und Timestamps', () async {
      final fs = FakeFirebaseFirestore();
      final ref = await fs.collection('tasks').add({
        'question': 'Was ist 3 × 3?',
        'options': ['6', '9'],
        'correctAnswer': '9',
        'solution': 'Multiplikation',
        'difficulty': 'medium',
        'topic': 'Einmaleins',
        'status': 'approved',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'approvedAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'approvedBy': 'parent1',
      });
      final doc = await ref.get();

      final q = GeneratedQuestion.fromFirestore(doc);
      expect(q.id, ref.id);
      expect(q.question, 'Was ist 3 × 3?');
      expect(q.options, ['6', '9']);
      expect(q.correctAnswer, '9');
      expect(q.status, TaskApprovalStatus.approved);
      expect(q.isAvailableForChild, isTrue);
      expect(q.approvedBy, 'parent1');
      expect(q.createdAt, DateTime(2026, 1, 1));
    });

    test('nutzt Defaults bei fehlenden Feldern', () async {
      final fs = FakeFirebaseFirestore();
      final ref = await fs.collection('tasks').add({'question': 'Q'});
      final doc = await ref.get();

      final q = GeneratedQuestion.fromFirestore(doc);
      expect(q.options, isEmpty);
      expect(q.difficulty, 'medium');
      expect(q.status, TaskApprovalStatus.pending);
    });
  });

  group('GeneratedTaskBatch.fromFirestore', () {
    test('liest gespeicherte Zähler', () async {
      final fs = FakeFirebaseFirestore();
      final ref = await fs.collection('batches').add({
        'childId': 'c1',
        'childName': 'Max',
        'subject': 'mathe',
        'imageUrl': 'http://x/y.jpg',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'totalTasks': 10,
        'approvedTasks': 4,
        'pendingTasks': 5,
        'rejectedTasks': 1,
      });
      final doc = await ref.get();

      final batch = GeneratedTaskBatch.fromFirestore(doc, const []);
      expect(batch.id, ref.id);
      expect(batch.subject, Subject.mathe);
      expect(batch.totalTasks, 10);
      expect(batch.approvedTasks, 4);
      expect(batch.pendingTasks, 5);
      expect(batch.rejectedTasks, 1);
      expect(batch.isFullyReviewed, isFalse);
    });

    test('alter Batch ohne Zähler → alles als pending behandelt', () async {
      final fs = FakeFirebaseFirestore();
      final ref = await fs.collection('batches').add({
        'childId': 'c1',
        'childName': 'Max',
        'subject': 'deutsch',
        'imageUrl': 'http://x/y.jpg',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'totalTasks': 8,
        // keine *_Tasks-Zähler
      });
      final doc = await ref.get();

      final batch = GeneratedTaskBatch.fromFirestore(doc, const []);
      expect(batch.subject, Subject.deutsch);
      expect(batch.pendingTasks, 8); // total als pending übernommen
      expect(batch.approvedTasks, 0);
      expect(batch.rejectedTasks, 0);
    });
  });
}
