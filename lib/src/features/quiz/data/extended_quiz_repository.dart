import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/question_model.dart';
import '../../auth/domain/child_model.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../generated_tasks/data/generated_task_models.dart';
import 'ai_question_cache_repository.dart';
import 'combined_quiz_params.dart';

/// 📚 ERWEITERTER QUIZ REPOSITORY v4
///
/// Laedt Quiz-Fragen mit klarer Prioritaet:
///   1. Von Eltern freigegebene Aufgaben (noch nicht beantwortet) → immer zuerst
///   2. Restliche Plaetze (bis questionCount) mit KI-Cache-Fragen auffuellen
///   3. Wenn KI-Cache leer: statische JSON-Fragen als Fallback
///
/// Beispiel bei questionCount = 5:
///   2 Eltern-Aufgaben  → 2 Eltern + 3 KI-Fragen
///   5+ Eltern-Aufgaben → 5 Eltern (keine KI noetig)
///   0 Eltern-Aufgaben  → 5 KI-Fragen
class ExtendedQuizRepository {
  final AiQuestionCacheRepository _cache;
  final GeneratedTaskRepository _taskRepo;

  ExtendedQuizRepository(this._cache, this._taskRepo);

  // == Oeffentliche API ==

  Future<List<Question>> loadQuizForChild({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int questionCount = 5,
  }) async {
    final result = <Question>[];

    // -------------------------------------------------------------------------
    // 1. Eltern-Aufgaben laden (hoechste Prioritaet)
    // -------------------------------------------------------------------------
    try {
      final subjectEnum = SubjectExtension.fromString(subject);
      final parentQuestions = await _taskRepo.getUnansweredApprovedQuestions(
        userId: userId,
        childId: childId,
        subject: subjectEnum,
      );

      if (parentQuestions.isNotEmpty) {
        final converted =
            parentQuestions
                .map(
                  (gq) => Question(
                    grade: child.grade,
                    question: gq.question,
                    options: gq.options,
                    answer: gq.correctAnswer,
                    difficulty: gq.difficulty,
                    topic: gq.topic,
                    parentTaskRef: gq.batchId != null
                        ? '${gq.batchId}/${gq.id}'
                        : null,
                    generatedTaskId: gq.id,
                  ),
                )
                .toList()
              ..shuffle();

        result.addAll(converted.take(questionCount));
        debugPrint('👨‍👩‍👧 ${result.length} Eltern-Aufgaben eingebaut');
      }
    } catch (e) {
      debugPrint('⚠️ Eltern-Aufgaben nicht verfuegbar: $e');
    }

    // Bereits genug Fragen durch Eltern-Aufgaben?
    if (result.length >= questionCount) {
      return result.take(questionCount).toList();
    }

    final remaining = questionCount - result.length;
    final parentTexts = result
        .map((q) => q.question.toLowerCase().trim())
        .toSet();

    // -------------------------------------------------------------------------
    // 2. KI-Fragen auffuellen
    // -------------------------------------------------------------------------
    try {
      final aiQuestions = await _cache.getQuestions(
        userId: userId,
        childId: childId,
        child: child,
        subject: subject,
        count: remaining + 5, // Etwas mehr holen fuer Deduplizierung
      );

      if (aiQuestions.isNotEmpty) {
        final deduped =
            _deduplicate(aiQuestions)
                .where(
                  (q) => !parentTexts.contains(q.question.toLowerCase().trim()),
                )
                .toList()
              ..shuffle();

        result.addAll(deduped.take(remaining));

        debugPrint(
          '✅ ${result.length}/$questionCount Fragen geladen '
          '(${result.where((q) => q.isParentTask).length} Eltern, '
          '${result.where((q) => !q.isParentTask).length} KI)',
        );

        if (result.length >= questionCount) {
          return result;
        }
      }
    } catch (e) {
      debugPrint('⚠️ KI-Cache nicht verfuegbar: $e');
    }

    // -------------------------------------------------------------------------
    // 3. Statische Fragen als Fallback fuer verbleibende Plaetze
    // -------------------------------------------------------------------------
    final stillNeeded = questionCount - result.length;
    if (stillNeeded > 0) {
      debugPrint('⚠️ Fuelle $stillNeeded Plaetze mit statischen Fragen auf...');
      try {
        final staticQuestions = await _loadStaticQuestions(
          subject,
          child.grade,
        );
        final existingTexts = result
            .map((q) => q.question.toLowerCase().trim())
            .toSet();

        final filtered =
            staticQuestions
                .where(
                  (q) =>
                      !existingTexts.contains(q.question.toLowerCase().trim()),
                )
                .toList()
              ..shuffle();

        result.addAll(filtered.take(stillNeeded));
      } catch (e) {
        debugPrint('⚠️ Statische Fragen nicht verfuegbar: $e');
      }
    }

    if (result.isEmpty) {
      debugPrint('❌ Keine Fragen fuer $subject Klasse ${child.grade} gefunden');
    }

    return result.take(questionCount).toList();
  }

  /// Laedt statische JSON-Fragen fuer ein Fach (Fallback).
  Future<QuizData> loadStaticQuizData(String subject) async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/questions/${subject.toLowerCase()}.json',
      );
      return QuizData.fromJson(json.decode(jsonString));
    } catch (e) {
      debugPrint(
        '⚠️ Fehler beim Laden der statischen Fragen fuer $subject: $e',
      );
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
