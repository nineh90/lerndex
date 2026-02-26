import 'question_model.dart';

/// Repräsentiert ein komplettes Quiz mit mehreren Fragen
class QuizData {
  final String subject; // Fach (Mathe, Deutsch, etc.)
  final List<Question> questions; // Alle Fragen

  QuizData({required this.subject, required this.questions});

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
