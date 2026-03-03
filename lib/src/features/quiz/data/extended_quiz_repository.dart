import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/question_model.dart';
import '../../auth/domain/child_model.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../generated_tasks/data/generated_task_models.dart';
import 'ai_question_cache_repository.dart';
import 'combined_quiz_params.dart';

/// 📚 ERWEITERTER QUIZ REPOSITORY v3
///
/// Laedt Quiz-Fragen mit klarer Prioritaet:
///   1. Von Eltern gepflegte & freigegebene Aufgaben (noch nicht korrekt beantwortet)
///   2. KI-generierte Fragen aus dem Cache (personalisiert, schulformgerecht)
///   3. Statische JSON-Fragen NUR als Notfall-Fallback
///
/// Logik: Solange noch unbeantwortete Eltern-Aufgaben vorhanden sind,
/// werden ausschließlich diese gezeigt. KI-Fragen kommen erst wenn
/// alle Eltern-Aufgaben korrekt beantwortet wurden.
class ExtendedQuizRepository {
  final AiQuestionCacheRepository _cache;
  final GeneratedTaskRepository _taskRepo;

  ExtendedQuizRepository(this._cache, this._taskRepo);

  // == Oeffentliche API ==

  /// Laedt eine Quiz-Session mit Prioritaet fuer Eltern-Aufgaben.
  ///
  /// Strategie:
  /// 1. Eltern-Aufgaben (approved, noch nicht korrekt beantwortet) → hoechste Prioritaet
  /// 2. Wenn keine Eltern-Aufgaben mehr: KI-Cache-Fragen
  /// 3. Wenn KI-Cache leer: statische JSON-Fragen als Fallback
  Future<List<Question>> loadQuizForChild({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int questionCount = 5,
  }) async {
    // -----------------------------------------------------------------------
    // 1. Eltern-gepflegte Aufgaben mit hoechster Prioritaet
    // -----------------------------------------------------------------------
    try {
      final subjectEnum = SubjectExtension.fromString(subject);
      final parentQuestions = await _taskRepo.getUnansweredApprovedQuestions(
        userId: userId,
        childId: childId,
        subject: subjectEnum,
      );

      if (parentQuestions.isNotEmpty) {
        print(
          '👨‍👩‍👧 ${parentQuestions.length} Eltern-Aufgaben vorhanden – '
          'KI-Fragen werden nicht genutzt bis alle beantwortet sind.',
        );

        // In Question-Objekte umwandeln mit parentTaskRef für Tracking
        final questions = parentQuestions.map((gq) {
          // Batch-ID aus dem approvedBy-Feld ist nicht verfügbar hier,
          // daher suchen wir den batchId über den parentTaskRef-Mechanismus.
          // Die batchId wird beim Laden mitgegeben über das id-Feld des Batch.
          // Wir codieren: "batchId/questionId" als parentTaskRef
          // Das batchId muss aus den Batches kommen – wir holen es über
          // eine erweiterte Version der Methode.
          return Question(
            grade: child.grade,
            question: gq.question,
            options: gq.options,
            answer: gq.correctAnswer,
            difficulty: gq.difficulty,
            topic: gq.topic,
            parentTaskRef: gq.batchId != null ? '${gq.batchId}/${gq.id}' : null,
          );
        }).toList();

        questions.shuffle();
        final result = questions.take(questionCount).toList();

        print('✅ ${result.length} Eltern-Aufgaben als Quiz geladen');
        return result;
      }

      print('ℹ️ Keine offenen Eltern-Aufgaben – lade KI-Fragen');
    } catch (e) {
      print(
        '⚠️ Eltern-Aufgaben nicht verfuegbar: $e – falle auf KI-Fragen zurueck',
      );
    }

    // -----------------------------------------------------------------------
    // 2. KI-Fragen aus Cache
    // -----------------------------------------------------------------------
    try {
      final aiQuestions = await _cache.getQuestions(
        userId: userId,
        childId: childId,
        child: child,
        subject: subject,
        count: questionCount,
      );

      if (aiQuestions.isNotEmpty) {
        print(
          '✅ ${aiQuestions.length} KI-Fragen geladen '
          '(${child.schoolType}, Kl. ${child.grade}, Lv. ${child.level})',
        );

        final deduped = _deduplicate(aiQuestions);
        deduped.shuffle();

        if (deduped.length >= questionCount) {
          return deduped.take(questionCount).toList();
        }

        // Zu wenig KI-Fragen: mit statischen auffuellen
        print(
          '⚠️ Nur ${deduped.length} KI-Fragen, fuelle mit statischen auf...',
        );
        final staticQuestions = await _loadStaticQuestions(
          subject,
          child.grade,
        );
        final existingTexts = deduped
            .map((q) => q.question.toLowerCase().trim())
            .toSet();
        final extraStatic = staticQuestions
            .where(
              (q) => !existingTexts.contains(q.question.toLowerCase().trim()),
            )
            .toList();
        extraStatic.shuffle();

        deduped.addAll(extraStatic.take(questionCount - deduped.length));
        return deduped.take(questionCount).toList();
      }
    } catch (e) {
      print('⚠️ KI-Cache nicht verfuegbar: $e');
    }

    // -----------------------------------------------------------------------
    // 3. Komplett-Fallback: Nur statische Fragen
    // -----------------------------------------------------------------------
    print('⚠️ Keine KI-Fragen verfuegbar, nutze statische Fragen als Fallback');
    final staticQuestions = await _loadStaticQuestions(subject, child.grade);

    if (staticQuestions.isEmpty) {
      print(
        '❌ Auch keine statischen Fragen fuer $subject Klasse ${child.grade}',
      );
      return [];
    }

    staticQuestions.shuffle();
    return staticQuestions.take(questionCount).toList();
  }

  /// Laedt statische JSON-Fragen fuer ein Fach (Fallback).
  Future<QuizData> loadStaticQuizData(String subject) async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/questions/${subject.toLowerCase()}.json',
      );
      return QuizData.fromJson(json.decode(jsonString));
    } catch (e) {
      print('⚠️ Fehler beim Laden der statischen Fragen fuer $subject: $e');
      return QuizData(subject: subject, questions: []);
    }
  }

  // == Interne Helfer ==

  Future<List<Question>> _loadStaticQuestions(String subject, int grade) async {
    try {
      final quizData = await loadStaticQuizData(subject);
      return quizData.getQuestionsForGrade(grade, count: 10);
    } catch (e) {
      return [];
    }
  }

  List<Question> _deduplicate(List<Question> questions) {
    final seen = <String>{};
    return questions.where((q) {
      final normalized = q.question.toLowerCase().trim();
      return seen.add(normalized);
    }).toList();
  }
}

// == Riverpod Providers ==

final extendedQuizRepositoryProvider = Provider<ExtendedQuizRepository>((ref) {
  return ExtendedQuizRepository(
    ref.watch(aiQuestionCacheRepositoryProvider),
    ref.watch(generatedTaskRepositoryProvider),
  );
});

/// Provider zum Laden einer kombinierten Quiz-Session
final combinedQuizSessionProvider =
    FutureProvider.family<List<Question>, CombinedQuizParams>((
      ref,
      params,
    ) async {
      final repository = ref.watch(extendedQuizRepositoryProvider);
      return repository.loadQuizForChild(
        userId: params.userId,
        childId: params.childId,
        child: params.child,
        subject: params.subject,
        questionCount: params.questionCount,
      );
    });
