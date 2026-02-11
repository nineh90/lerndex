import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/question_model.dart';
import '../../generated_tasks/data/generated_task_models.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../auth/data/auth_repository.dart';

/// 📚 ERWEITERTER QUIZ REPOSITORY
///
/// Kombiniert zwei Quellen von Fragen:
/// 1. Statische Fragen aus JSON-Dateien (assets/questions/)
/// 2. Dynamische, freigegebene KI-generierte Aufgaben
///
/// Die generierten Aufgaben werden nahtlos in das bestehende Quiz-System integriert

class ExtendedQuizRepository {
  final GeneratedTaskRepository _generatedTaskRepo;

  ExtendedQuizRepository(this._generatedTaskRepo);

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

  /// Lädt eine kombinierte Quiz-Session aus statischen UND generierten Aufgaben
  ///
  /// Strategie:
  /// 1. Lade statische Fragen aus JSON
  /// 2. Lade freigegebene KI-Aufgaben für dieses Kind und Fach
  /// 3. Mische beide Quellen
  /// 4. Gib gewünschte Anzahl zurück
  Future<List<Question>> loadQuizForChild({
    required String userId,
    required String childId,
    required String subject,
    required int grade,
    int questionCount = 5,
    bool includeGenerated = true,
  }) async {
    final allQuestions = <Question>[];

    // 1. Statische Fragen laden
    try {
      final quizData = await loadQuestions(subject);
      final staticQuestions = quizData.getQuestionsForGrade(
        grade,
        count: questionCount * 2, // Mehr laden für bessere Mischung
      );
      allQuestions.addAll(staticQuestions);
    } catch (e) {
      print('⚠️ Fehler beim Laden statischer Fragen: $e');
    }

    // 2. Generierte Fragen laden (falls aktiviert)
    if (includeGenerated) {
      try {
        final subjectEnum = _subjectStringToEnum(subject);
        final generatedQuestions = await _generatedTaskRepo.getApprovedQuestionsForChild(
          userId: userId,
          childId: childId,
          subject: subjectEnum,
        );

        // Konvertiere zu Question-Objekten
        for (var generated in generatedQuestions) {
          allQuestions.add(_convertToQuestion(generated, grade));
        }

        print('✅ ${generatedQuestions.length} generierte Aufgaben hinzugefügt');
      } catch (e) {
        print('⚠️ Fehler beim Laden generierter Fragen: $e');
      }
    }

    // 3. Mischen und gewünschte Anzahl zurückgeben
    if (allQuestions.isEmpty) {
      print('⚠️ Keine Fragen verfügbar für $subject');
      return [];
    }

    allQuestions.shuffle();
    return allQuestions.take(questionCount).toList();
  }

  /// Lädt NUR generierte Aufgaben für ein Kind
  Future<List<Question>> loadGeneratedQuestionsOnly({
    required String userId,
    required String childId,
    required String subject,
    required int grade,
  }) async {
    try {
      final subjectEnum = _subjectStringToEnum(subject);
      final generatedQuestions = await _generatedTaskRepo.getApprovedQuestionsForChild(
        userId: userId,
        childId: childId,
        subject: subjectEnum,
      );

      return generatedQuestions
          .map((g) => _convertToQuestion(g, grade))
          .toList();
    } catch (e) {
      print('❌ Fehler beim Laden generierter Fragen: $e');
      return [];
    }
  }

  /// Gibt Statistiken über verfügbare Fragen zurück
  Future<QuizStatistics> getQuizStatistics({
    required String userId,
    required String childId,
    required String subject,
    required int grade,
  }) async {
    int staticCount = 0;
    int generatedCount = 0;

    // Zähle statische Fragen
    try {
      final quizData = await loadQuestions(subject);
      staticCount = quizData.questions.where((q) => q.grade == grade).length;
    } catch (e) {
      print('⚠️ Fehler beim Zählen statischer Fragen: $e');
    }

    // Zähle generierte Fragen
    try {
      final subjectEnum = _subjectStringToEnum(subject);
      final generated = await _generatedTaskRepo.getApprovedQuestionsForChild(
        userId: userId,
        childId: childId,
        subject: subjectEnum,
      );
      generatedCount = generated.length;
    } catch (e) {
      print('⚠️ Fehler beim Zählen generierter Fragen: $e');
    }

    return QuizStatistics(
      subject: subject,
      grade: grade,
      staticQuestionCount: staticCount,
      generatedQuestionCount: generatedCount,
      totalQuestionCount: staticCount + generatedCount,
    );
  }

  // ========================================================================
  // HILFSMETHODEN
  // ========================================================================

  /// Konvertiert eine GeneratedQuestion in eine Question
  Question _convertToQuestion(GeneratedQuestion generated, int grade) {
    return Question(
      grade: grade,
      question: generated.question,
      options: generated.options,
      answer: generated.correctAnswer,
      difficulty: generated.difficulty,
    );
  }

  /// Konvertiert Subject-String zu Subject-Enum
  Subject _subjectStringToEnum(String subject) {
    switch (subject.toLowerCase()) {
      case 'deutsch':
        return Subject.deutsch;
      case 'englisch':
        return Subject.englisch;
      case 'sachkunde':
        return Subject.sachkunde;
      default:
        return Subject.mathe;
    }
  }
}

/// 📊 QUIZ STATISTIKEN
class QuizStatistics {
  final String subject;
  final int grade;
  final int staticQuestionCount;
  final int generatedQuestionCount;
  final int totalQuestionCount;

  QuizStatistics({
    required this.subject,
    required this.grade,
    required this.staticQuestionCount,
    required this.generatedQuestionCount,
    required this.totalQuestionCount,
  });

  bool get hasGeneratedQuestions => generatedQuestionCount > 0;
  bool get hasStaticQuestions => staticQuestionCount > 0;

  double get generatedPercentage {
    if (totalQuestionCount == 0) return 0;
    return (generatedQuestionCount / totalQuestionCount * 100);
  }
}

// ========================================================================
// RIVERPOD PROVIDERS
// ========================================================================

/// Provider für ExtendedQuizRepository
final extendedQuizRepositoryProvider = Provider<ExtendedQuizRepository>((ref) {
  final generatedTaskRepo = ref.watch(generatedTaskRepositoryProvider);
  return ExtendedQuizRepository(generatedTaskRepo);
});

/// Provider zum Laden einer kombinierten Quiz-Session
final combinedQuizSessionProvider = FutureProvider.family<List<Question>, CombinedQuizParams>(
      (ref, params) async {
    final repository = ref.watch(extendedQuizRepositoryProvider);
    return repository.loadQuizForChild(
      userId: params.userId,
      childId: params.childId,
      subject: params.subject,
      grade: params.grade,
      questionCount: params.questionCount,
      includeGenerated: params.includeGenerated,
    );
  },
);

/// Provider für Quiz-Statistiken
final quizStatisticsProvider = FutureProvider.family<QuizStatistics, QuizStatisticsParams>(
      (ref, params) async {
    final repository = ref.watch(extendedQuizRepositoryProvider);
    return repository.getQuizStatistics(
      userId: params.userId,
      childId: params.childId,
      subject: params.subject,
      grade: params.grade,
    );
  },
);

// ========================================================================
// PARAMETER-KLASSEN
// ========================================================================

/// Parameter für kombinierte Quiz-Session
class CombinedQuizParams {
  final String userId;
  final String childId;
  final String subject;
  final int grade;
  final int questionCount;
  final bool includeGenerated;

  CombinedQuizParams({
    required this.userId,
    required this.childId,
    required this.subject,
    required this.grade,
    this.questionCount = 5,
    this.includeGenerated = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is CombinedQuizParams &&
              runtimeType == other.runtimeType &&
              userId == other.userId &&
              childId == other.childId &&
              subject == other.subject &&
              grade == other.grade &&
              questionCount == other.questionCount &&
              includeGenerated == other.includeGenerated;

  @override
  int get hashCode =>
      userId.hashCode ^
      childId.hashCode ^
      subject.hashCode ^
      grade.hashCode ^
      questionCount.hashCode ^
      includeGenerated.hashCode;
}

/// Parameter für Quiz-Statistiken
class QuizStatisticsParams {
  final String userId;
  final String childId;
  final String subject;
  final int grade;

  QuizStatisticsParams({
    required this.userId,
    required this.childId,
    required this.subject,
    required this.grade,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is QuizStatisticsParams &&
              runtimeType == other.runtimeType &&
              userId == other.userId &&
              childId == other.childId &&
              subject == other.subject &&
              grade == other.grade;

  @override
  int get hashCode =>
      userId.hashCode ^
      childId.hashCode ^
      subject.hashCode ^
      grade.hashCode;
}