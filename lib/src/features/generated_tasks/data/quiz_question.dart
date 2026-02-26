import 'generated_task_models.dart';

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
