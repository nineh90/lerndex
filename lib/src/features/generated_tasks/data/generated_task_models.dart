import 'package:cloud_firestore/cloud_firestore.dart';

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

/// 📦 BATCH VON GENERIERTEN AUFGABEN
/// Ein Batch repräsentiert alle Aufgaben, die aus einem hochgeladenen Foto generiert wurden
class GeneratedTaskBatch {
  final String id;
  final String childId;
  final String childName;
  final Subject subject;
  final String imageUrl;
  final DateTime createdAt;
  final int totalTasks;
  final int approvedTasks;
  final int pendingTasks;
  final int rejectedTasks;
  final List<GeneratedQuestion> questions;

  GeneratedTaskBatch({
    required this.id,
    required this.childId,
    required this.childName,
    required this.subject,
    required this.imageUrl,
    required this.createdAt,
    required this.totalTasks,
    required this.approvedTasks,
    required this.pendingTasks,
    required this.rejectedTasks,
    required this.questions,
  });

  factory GeneratedTaskBatch.fromFirestore(
    DocumentSnapshot doc,
    List<GeneratedQuestion> questions,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    // Zähle Status
    final approved = questions
        .where((q) => q.status == TaskApprovalStatus.approved)
        .length;
    final pending = questions
        .where((q) => q.status == TaskApprovalStatus.pending)
        .length;
    final rejected = questions
        .where((q) => q.status == TaskApprovalStatus.rejected)
        .length;

    return GeneratedTaskBatch(
      id: doc.id,
      childId: data['childId'] ?? '',
      childName: data['childName'] ?? '',
      subject: SubjectExtension.fromString(data['subject'] ?? 'mathe'),
      imageUrl: data['imageUrl'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalTasks: questions.length,
      approvedTasks: approved,
      pendingTasks: pending,
      rejectedTasks: rejected,
      questions: questions,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'childName': childName,
      'subject': subject.value,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'totalTasks': totalTasks,
    };
  }

  /// Gibt true zurück, wenn alle Aufgaben bearbeitet wurden (approved oder rejected)
  bool get isFullyReviewed => pendingTasks == 0;

  /// Gibt true zurück, wenn mindestens eine Aufgabe freigegeben wurde
  bool get hasApprovedTasks => approvedTasks > 0;

  /// Fortschritt der Freigabe in Prozent (0-100)
  double get reviewProgress {
    if (totalTasks == 0) return 0;
    return ((approvedTasks + rejectedTasks) / totalTasks * 100);
  }
}

/// 🎯 QUIZ-FRAGE (Konvertiert aus GeneratedQuestion für Quiz-System)
/// Diese Klasse ist kompatibel mit der Question-Klasse aus dem Quiz-System
class QuizQuestion {
  final int grade;
  final String question;
  final List<String> options;
  final String answer;
  final String difficulty;
  final String? generatedTaskId; // Referenz zur originalen generierten Aufgabe

  QuizQuestion({
    required this.grade,
    required this.question,
    required this.options,
    required this.answer,
    required this.difficulty,
    this.generatedTaskId,
  });

  /// Erstellt eine QuizQuestion aus einer GeneratedQuestion
  factory QuizQuestion.fromGeneratedQuestion(
    GeneratedQuestion generated,
    int grade,
  ) {
    return QuizQuestion(
      grade: grade,
      question: generated.question,
      options: generated.options,
      answer: generated.correctAnswer,
      difficulty: generated.difficulty,
      generatedTaskId: generated.id,
    );
  }

  /// Prüft ob die gegebene Antwort richtig ist
  bool isCorrect(String selectedAnswer) {
    return selectedAnswer == answer;
  }

  /// Konvertiert zu JSON (kompatibel mit Question-Klasse)
  Map<String, dynamic> toJson() {
    return {
      'grade': grade,
      'question': question,
      'options': options,
      'answer': answer,
      'difficulty': difficulty,
    };
  }
}
