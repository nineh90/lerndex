/// Repräsentiert eine Quiz-Frage
class Question {
  final int grade;              // Klassenstufe (1-13)
  final String question;        // Die Frage
  final List<String> options;   // Antwortmöglichkeiten (4 Stück)
  final String answer;          // Richtige Antwort
  final String difficulty;      // Schwierigkeitsgrad: easy, medium, hard

  Question({
    required this.grade,
    required this.question,
    required this.options,
    required this.answer,
    required this.difficulty,
  });

  /// Erstellt eine Question aus JSON
  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      grade: json['grade'] as int,
      question: json['question'] as String,
      options: List<String>.from(json['options']),
      answer: json['answer'] as String,
      difficulty: json['difficulty'] as String,
    );
  }

  /// Prüft ob die gegebene Antwort richtig ist
  bool isCorrect(String selectedAnswer) {
    return selectedAnswer == answer;
  }
}

/// Repräsentiert ein komplettes Quiz mit mehreren Fragen
class QuizData {
  final String subject;           // Fach (Mathe, Deutsch, etc.)
  final List<Question> questions; // Alle Fragen

  QuizData({
    required this.subject,
    required this.questions,
  });

  /// Erstellt QuizData aus JSON
  factory QuizData.fromJson(Map<String, dynamic> json) {
    return QuizData(
      subject: json['subject'] as String,
      questions: (json['questions'] as List)
          .map((q) => Question.fromJson(q))
          .toList(),
    );
  }

  /// Filtert Fragen nach Klassenstufe
  /// Gibt 5 zufällige Fragen für die angegebene Klasse zurück
  List<Question> getQuestionsForGrade(int grade, {int count = 5}) {
    // Fragen für diese Klasse filtern
    var filtered = questions.where((q) => q.grade == grade).toList();

    // Wenn nicht genug Fragen: auch Fragen aus Klasse -1 und +1 nehmen
    if (filtered.length < count) {
      filtered.addAll(
        questions.where((q) => q.grade == grade - 1 || q.grade == grade + 1),
      );
    }

    // Mischen und erste 'count' Fragen zurückgeben
    filtered.shuffle();
    return filtered.take(count).toList();
  }
}