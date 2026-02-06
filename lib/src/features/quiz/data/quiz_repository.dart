import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/question_model.dart';

/// Repository zum Laden der Quiz-Fragen aus JSON-Dateien
class QuizRepository {
  /// Lädt Fragen für ein bestimmtes Fach
  /// subject: 'mathe', 'deutsch', 'englisch', 'sachkunde'
  Future<QuizData> loadQuestions(String subject) async {
    try {
      // JSON-Datei aus assets laden
      final jsonString = await rootBundle.loadString(
        'assets/questions/${subject.toLowerCase()}.json',
      );

      // JSON parsen
      final jsonData = json.decode(jsonString);

      // In QuizData umwandeln
      return QuizData.fromJson(jsonData);
    } catch (e) {
      print('Fehler beim Laden der Fragen für $subject: $e');
      // Fallback: Leere QuizData zurückgeben
      return QuizData(subject: subject, questions: []);
    }
  }

  /// Lädt eine personalisierte Quiz-Session
  /// Filtert automatisch nach Klassenstufe des Kindes
  Future<List<Question>> loadQuizForChild({
    required String subject,
    required int grade,
    int questionCount = 5,
  }) async {
    final quizData = await loadQuestions(subject);
    return quizData.getQuestionsForGrade(grade, count: questionCount);
  }
}

/// Provider für QuizRepository
final quizRepositoryProvider = Provider<QuizRepository>((ref) {
  return QuizRepository();
});

/// Provider zum Laden der Fragen für ein Fach
/// Verwendung: ref.watch(quizQuestionsProvider('mathe'))
final quizQuestionsProvider = FutureProvider.family<QuizData, String>((ref, subject) async {
  final repository = ref.watch(quizRepositoryProvider);
  return repository.loadQuestions(subject);
});