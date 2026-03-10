export 'quiz_data.dart';

/// Repräsentiert eine Quiz-Frage.
///
/// Diese Klasse ist die EINZIGE Question-Klasse im gesamten Projekt.
/// Sie ersetzt die frühere QuizQuestion-Klasse vollständig.
///
/// Quellen:
///   - KI-generierte Fragen (via VertexAIService / AiQuestionCacheRepository)
///   - Von Eltern freigegebene Aufgaben (parentTaskRef != null)
///   - Statische JSON-Fallback-Fragen
class Question {
  final int grade;
  final String question;
  final List<String> options;
  final String answer;
  final String difficulty;
  final String topic;

  /// Wenn gesetzt: Diese Frage stammt von einem Eltern-gepflegten Task.
  /// Format: "batchId/questionId"
  /// Wird beim korrekten Beantworten in Firestore markiert.
  final String? parentTaskRef;

  /// Optionale Referenz zur ursprünglichen generierten Aufgaben-ID.
  /// Entspricht GeneratedQuestion.id — wird für Task-Tracking genutzt.
  final String? generatedTaskId;

  const Question({
    required this.grade,
    required this.question,
    required this.options,
    required this.answer,
    required this.difficulty,
    this.topic = '',
    this.parentTaskRef,
    this.generatedTaskId,
  });

  // ── Factories ──────────────────────────────────────────────────────────────

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      grade: json['grade'] as int? ?? 1,
      question: json['question'] as String,
      options: List<String>.from(json['options']),
      answer: json['answer'] as String,
      difficulty: json['difficulty'] as String? ?? 'medium',
      topic: json['topic'] as String? ?? '',
      parentTaskRef: json['parentTaskRef'] as String?,
      generatedTaskId: json['generatedTaskId'] as String?,
    );
  }

  // ── Methoden ───────────────────────────────────────────────────────────────

  bool isCorrect(String selectedAnswer) => selectedAnswer == answer;

  /// True wenn diese Frage von Eltern gepflegt wurde
  bool get isParentTask => parentTaskRef != null;

  Map<String, dynamic> toJson() {
    return {
      'grade': grade,
      'question': question,
      'options': options,
      'answer': answer,
      'difficulty': difficulty,
      'topic': topic,
      if (parentTaskRef != null) 'parentTaskRef': parentTaskRef,
      if (generatedTaskId != null) 'generatedTaskId': generatedTaskId,
    };
  }

  Question copyWith({
    int? grade,
    String? question,
    List<String>? options,
    String? answer,
    String? difficulty,
    String? topic,
    String? parentTaskRef,
    String? generatedTaskId,
  }) {
    return Question(
      grade: grade ?? this.grade,
      question: question ?? this.question,
      options: options ?? List<String>.from(this.options),
      answer: answer ?? this.answer,
      difficulty: difficulty ?? this.difficulty,
      topic: topic ?? this.topic,
      parentTaskRef: parentTaskRef ?? this.parentTaskRef,
      generatedTaskId: generatedTaskId ?? this.generatedTaskId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Question &&
          runtimeType == other.runtimeType &&
          question == other.question &&
          answer == other.answer &&
          grade == other.grade;

  @override
  int get hashCode => Object.hash(question, answer, grade);

  @override
  String toString() =>
      'Question(grade: $grade, topic: $topic, difficulty: $difficulty, '
      'q: "${question.length > 50 ? "${question.substring(0, 50)}..." : question}")';
}
