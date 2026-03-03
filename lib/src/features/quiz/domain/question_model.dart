export 'quiz_data.dart';

/// Repräsentiert eine Quiz-Frage
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

  Question({
    required this.grade,
    required this.question,
    required this.options,
    required this.answer,
    required this.difficulty,
    this.topic = '',
    this.parentTaskRef,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      grade: json['grade'] as int,
      question: json['question'] as String,
      options: List<String>.from(json['options']),
      answer: json['answer'] as String,
      difficulty: json['difficulty'] as String,
      topic: json['topic'] as String? ?? '',
    );
  }

  bool isCorrect(String selectedAnswer) => selectedAnswer == answer;

  /// True wenn diese Frage von Eltern gepflegt wurde
  bool get isParentTask => parentTaskRef != null;
}

/// Repräsentiert ein komplettes Quiz mit mehreren Fragen
class QuizData {
  final String subject;
  final List<Question> questions;

  QuizData({required this.subject, required this.questions});

  factory QuizData.fromJson(Map<String, dynamic> json) {
    return QuizData(
      subject: json['subject'] as String,
      questions: (json['questions'] as List)
          .map((q) => Question.fromJson(q))
          .toList(),
    );
  }

  List<Question> getQuestionsForGrade(int grade, {int count = 5}) {
    var filtered = questions.where((q) => q.grade == grade).toList();
    if (filtered.length < count) {
      filtered.addAll(
        questions.where((q) => q.grade == grade - 1 || q.grade == grade + 1),
      );
    }
    filtered.shuffle();
    return filtered.take(count).toList();
  }
}
