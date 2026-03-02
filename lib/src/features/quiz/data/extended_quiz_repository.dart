import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/question_model.dart';
import '../../auth/domain/child_model.dart';
import 'ai_question_cache_repository.dart';
import 'combined_quiz_params.dart';

/// 📚 ERWEITERTER QUIZ REPOSITORY v2
///
/// Laedt Quiz-Fragen mit klarer Prioritaet:
///   1. KI-generierte Fragen aus dem Cache (personalisiert, schulformgerecht)
///   2. Statische JSON-Fragen NUR als Notfall-Fallback wenn KI komplett versagt
///
/// Aenderungen gegenueber v1:
///   - Statische Fragen werden NICHT mehr beigemischt (waren Duplikat-Quelle!)
///   - KI-Fragen haben volle Prioritaet (sind personalisiert)
///   - Statische Fragen nur noch wenn KI 0 Fragen liefert
///   - Deduplizierung basierend auf normalisiertem Fragetext
class ExtendedQuizRepository {
  final AiQuestionCacheRepository _cache;

  ExtendedQuizRepository(this._cache);

  // == Oeffentliche API ==

  /// Laedt eine Quiz-Session.
  ///
  /// Strategie:
  /// 1. Versuche KI-Fragen aus dem Cache zu laden (personalisiert!)
  /// 2. NUR wenn KI komplett versagt -> statische Fragen als Fallback
  /// 3. Mischen und Deduplizierung
  Future<List<Question>> loadQuizForChild({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int questionCount = 5,
  }) async {
    // 1. KI-Fragen aus Cache (personalisiert, schulformgerecht, level-abhaengig)
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

        // Deduplizieren (sollte nicht noetig sein, aber sicherheitshalber)
        final deduped = _deduplicate(aiQuestions);
        deduped.shuffle();

        // Wenn genug KI-Fragen: fertig
        if (deduped.length >= questionCount) {
          return deduped.take(questionCount).toList();
        }

        // Wenn zu wenig KI-Fragen: mit statischen auffuellen
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

    // 2. Komplett-Fallback: Nur statische Fragen
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

  /// Entfernt Duplikate basierend auf dem normalisierten Fragetext
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
  return ExtendedQuizRepository(ref.watch(aiQuestionCacheRepositoryProvider));
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
