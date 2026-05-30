import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';

void main() {
  group('Subject.isAvailableForGrade', () {
    test('Mathe ab Klasse 3', () {
      expect(Subject.mathe.isAvailableForGrade(3), isTrue);
      expect(Subject.mathe.isAvailableForGrade(13), isTrue);
      expect(Subject.mathe.isAvailableForGrade(1), isFalse);
    });
    test('farbenFormen nur Klasse 1–2', () {
      expect(Subject.farbenFormen.isAvailableForGrade(1), isTrue);
      expect(Subject.farbenFormen.isAvailableForGrade(2), isTrue);
      expect(Subject.farbenFormen.isAvailableForGrade(3), isFalse);
    });
    test('Sachkunde nur Klasse 3–4', () {
      expect(Subject.sachkunde.isAvailableForGrade(4), isTrue);
      expect(Subject.sachkunde.isAvailableForGrade(5), isFalse);
    });
    test('Biologie ab Klasse 5', () {
      expect(Subject.biologie.isAvailableForGrade(5), isTrue);
      expect(Subject.biologie.isAvailableForGrade(4), isFalse);
    });
  });

  group('Subject.forGrade', () {
    test('Klasse 1 → nur farbenFormen (Early Learner)', () {
      expect(SubjectExtension.forGrade(1), [Subject.farbenFormen]);
    });
    test('Klasse 3 → Grundschulfächer', () {
      final subjects = SubjectExtension.forGrade(3);
      expect(subjects, containsAll([
        Subject.mathe,
        Subject.deutsch,
        Subject.englisch,
        Subject.sachkunde,
      ]));
      expect(subjects, isNot(contains(Subject.biologie)));
    });
    test('Klasse 7 → weiterführende Fächer ohne Sachkunde', () {
      final subjects = SubjectExtension.forGrade(7);
      expect(subjects, contains(Subject.biologie));
      expect(subjects, contains(Subject.geschichte));
      expect(subjects, isNot(contains(Subject.sachkunde)));
      expect(subjects, isNot(contains(Subject.farbenFormen)));
    });
  });

  group('SubjectExtension.fromString', () {
    test('mappt direkte Fachnamen', () {
      expect(SubjectExtension.fromString('deutsch'), Subject.deutsch);
      expect(SubjectExtension.fromString('Biologie'), Subject.biologie);
    });
    test('Early-Learner-Aliase', () {
      expect(SubjectExtension.fromString('zahlen'), Subject.mathe);
      expect(SubjectExtension.fromString('buchstaben'), Subject.deutsch);
      expect(SubjectExtension.fromString('farben & formen'),
          Subject.farbenFormen);
      expect(SubjectExtension.fromString('farben'), Subject.farbenFormen);
    });
    test('unbekannt → mathe (Fallback)', () {
      expect(SubjectExtension.fromString('unbekannt'), Subject.mathe);
    });
  });

  group('Subject.value & displayName', () {
    test('value ist der Enum-Name', () {
      expect(Subject.mathe.value, 'mathe');
      expect(Subject.farbenFormen.value, 'farbenFormen');
    });
    test('displayName ist menschenlesbar', () {
      expect(Subject.mathe.displayName, 'Mathematik');
      expect(Subject.farbenFormen.displayName, 'Farben & Formen');
    });
  });

  group('TaskApprovalStatus', () {
    test('fromString mappt korrekt', () {
      expect(TaskApprovalStatusExtension.fromString('approved'),
          TaskApprovalStatus.approved);
      expect(TaskApprovalStatusExtension.fromString('rejected'),
          TaskApprovalStatus.rejected);
      expect(TaskApprovalStatusExtension.fromString('irgendwas'),
          TaskApprovalStatus.pending);
    });
    test('value Roundtrip', () {
      for (final status in TaskApprovalStatus.values) {
        expect(TaskApprovalStatusExtension.fromString(status.value), status);
      }
    });
    test('displayName ist gesetzt', () {
      expect(TaskApprovalStatus.approved.displayName, 'Freigegeben');
    });
  });

  group('GeneratedQuestion', () {
    GeneratedQuestion make(TaskApprovalStatus status) => GeneratedQuestion(
          id: 'q1',
          question: 'Frage?',
          options: const ['a', 'b', 'c', 'd'],
          correctAnswer: 'a',
          difficulty: 'medium',
          topic: 'Bruchrechnung',
          status: status,
          createdAt: DateTime(2026, 1, 1),
        );

    test('isAvailableForChild nur wenn approved', () {
      expect(make(TaskApprovalStatus.approved).isAvailableForChild, isTrue);
      expect(make(TaskApprovalStatus.pending).isAvailableForChild, isFalse);
      expect(make(TaskApprovalStatus.rejected).isAvailableForChild, isFalse);
    });

    test('copyWith ändert Status, behält Inhalt', () {
      final pending = make(TaskApprovalStatus.pending);
      final approved = pending.copyWith(
        status: TaskApprovalStatus.approved,
        approvedBy: 'parent1',
      );
      expect(approved.status, TaskApprovalStatus.approved);
      expect(approved.approvedBy, 'parent1');
      expect(approved.question, 'Frage?');
      expect(approved.correctAnswer, 'a');
    });
  });
}
