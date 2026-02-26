import 'package:cloud_firestore/cloud_firestore.dart';

export 'generated_task_batch.dart';
export 'quiz_question.dart';

/// 🎯 STATUS EINER GENERIERTEN AUFGABE
enum TaskApprovalStatus {
  pending, // Wartet auf Freigabe
  approved, // Von Eltern freigegeben
  rejected, // Von Eltern abgelehnt
}

extension TaskApprovalStatusExtension on TaskApprovalStatus {
  String get displayName {
    switch (this) {
      case TaskApprovalStatus.pending:
        return 'Ausstehend';
      case TaskApprovalStatus.approved:
        return 'Freigegeben';
      case TaskApprovalStatus.rejected:
        return 'Abgelehnt';
    }
  }

  String get value {
    return toString().split('.').last;
  }

  static TaskApprovalStatus fromString(String value) {
    switch (value) {
      case 'approved':
        return TaskApprovalStatus.approved;
      case 'rejected':
        return TaskApprovalStatus.rejected;
      default:
        return TaskApprovalStatus.pending;
    }
  }
}

/// 📚 FACH-TYPEN (muss mit Quiz-System kompatibel sein)
enum Subject {
  mathe,
  deutsch,
  englisch,
  sachkunde,
  biologie,
  chemie,
  physik,
  geschichte,
}

extension SubjectExtension on Subject {
  String get displayName {
    switch (this) {
      case Subject.mathe:
        return 'Mathematik';
      case Subject.deutsch:
        return 'Deutsch';
      case Subject.englisch:
        return 'Englisch';
      case Subject.sachkunde:
        return 'Sachkunde';
      case Subject.biologie:
        return 'Biologie';
      case Subject.chemie:
        return 'Chemie';
      case Subject.physik:
        return 'Physik';
      case Subject.geschichte:
        return 'Geschichte';
    }
  }

  String get value {
    return toString().split('.').last;
  }

  /// Verfügbare Klassen je Fach – abgeleitet aus den assets/questions/*.json
  static const Map<Subject, List<int>> availableGrades = {
    Subject.mathe: [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    Subject.deutsch: [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    Subject.englisch: [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    Subject.sachkunde: [3, 4],
    Subject.biologie: [5, 6, 7, 8, 9, 10],
    Subject.chemie: [5, 6, 7, 8, 9, 10, 11, 12, 13],
    Subject.physik: [5, 6, 7, 8, 9, 10, 11, 12, 13],
    Subject.geschichte: [5, 6, 7, 8, 9, 10, 11, 12, 13],
  };

  /// Prüft ob das Fach für die angegebene Klasse Fragen enthält
  bool isAvailableForGrade(int grade) {
    return availableGrades[this]?.contains(grade) ?? false;
  }

  static Subject fromString(String value) {
    switch (value.toLowerCase()) {
      case 'deutsch':
        return Subject.deutsch;
      case 'englisch':
        return Subject.englisch;
      case 'sachkunde':
        return Subject.sachkunde;
      case 'biologie':
        return Subject.biologie;
      case 'chemie':
        return Subject.chemie;
      case 'physik':
        return Subject.physik;
      case 'geschichte':
        return Subject.geschichte;
      default:
        return Subject.mathe;
    }
  }
}

/// 📝 EINZELNE GENERIERTE AUFGABE
class GeneratedQuestion {
  final String id;
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String? solution; // Optionale ausführliche Lösung
  final String difficulty; // easy, medium, hard
  final String topic; // z.B. "Bruchrechnung", "Grammatik"
  final TaskApprovalStatus status;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final String? approvedBy; // Eltern-User-ID
  final String? rejectionReason;

  GeneratedQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctAnswer,
    this.solution,
    required this.difficulty,
    required this.topic,
    required this.status,
    required this.createdAt,
    this.approvedAt,
    this.approvedBy,
    this.rejectionReason,
  });

  factory GeneratedQuestion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GeneratedQuestion(
      id: doc.id,
      question: data['question'] ?? '',
      options: List<String>.from(data['options'] ?? []),
      correctAnswer: data['correctAnswer'] ?? '',
      solution: data['solution'],
      difficulty: data['difficulty'] ?? 'medium',
      topic: data['topic'] ?? '',
      status: TaskApprovalStatusExtension.fromString(
        data['status'] ?? 'pending',
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      approvedBy: data['approvedBy'],
      rejectionReason: data['rejectionReason'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'question': question,
      'options': options,
      'correctAnswer': correctAnswer,
      'solution': solution,
      'difficulty': difficulty,
      'topic': topic,
      'status': status.value,
      'createdAt': FieldValue.serverTimestamp(),
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'approvedBy': approvedBy,
      'rejectionReason': rejectionReason,
    };
  }

  /// Kopie mit geändertem Status erstellen
  GeneratedQuestion copyWith({
    TaskApprovalStatus? status,
    DateTime? approvedAt,
    String? approvedBy,
    String? rejectionReason,
  }) {
    return GeneratedQuestion(
      id: id,
      question: question,
      options: options,
      correctAnswer: correctAnswer,
      solution: solution,
      difficulty: difficulty,
      topic: topic,
      status: status ?? this.status,
      createdAt: createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  /// Prüft ob die Frage vom Kind beantwortet werden darf
  bool get isAvailableForChild => status == TaskApprovalStatus.approved;
}
