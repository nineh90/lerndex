import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/question_model.dart';
import '../../auth/domain/child_model.dart';
import 'ai_question_cache_repository.dart';
import 'combined_quiz_params.dart';

/// 📚 ERWEITERTER QUIZ REPOSITORY
///
/// Kombiniert zwei Quellen von Fragen:
///   1. Statische Fragen aus JSON-Dateien (assets/questions/)
///   2. KI-generierte Fragen aus dem Firestore-Cache (kein Approval nötig)
///
/// Strategie:
///   - Zuerst statische Fragen laden (schnell, immer verfügbar)
///   - Ergänzt/ersetzt durch KI-Fragen aus dem Cache
///   - Falls KI-Cache leer → KI generiert on-the-fly (2-3s Ladezeit)
///   - Falls KI komplett nicht erreichbar → nur statische Fragen
class ExtendedQuizRepository {
  final AiQuestionCacheRepository _cache;

  ExtendedQuizRepository(this._cache);

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Lädt eine gemischte Quiz-Session aus statischen + KI-Fragen.
  ///
  /// Verhältnis: 2 statische + 3 KI-generierte (bei 5 Fragen).
  /// Bei weniger verfügbaren KI-Fragen wird der Rest statisch aufgefüllt.
  Future<List<Question>> loadQuizForChild({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int questionCount = 5,
  }) async {
    final allQuestions = <Question>[];

    // 1. Statische Fragen laden (immer als Fallback)
    final staticQuestions = await _loadStaticQuestions(subject, child.grade);
    allQuestions.addAll(staticQuestions);

    // 2. KI-Fragen aus Cache holen
    try {
      final aiQuestions = await _cache.getQuestions(
        userId: userId,
        childId: childId,
        child: child,
        subject: subject,
        count: questionCount,
      );
      // KI-Fragen vorne einmischen (höhere Priorität)
      allQuestions.insertAll(0, aiQuestions);
      print(
        '✅ ${aiQuestions.length} KI-Fragen + ${staticQuestions.length} statische Fragen geladen',
      );
    } catch (e) {
      print('⚠️ KI-Cache nicht verfügbar, nur statische Fragen: $e');
    }

    if (allQuestions.isEmpty) return [];

    // Mischen und gewünschte Anzahl zurückgeben
    // Duplikate entfernen (gleicher Fragetext)
    final seen = <String>{};
    final deduped = allQuestions.where((q) => seen.add(q.question)).toList();
    deduped.shuffle();
    return deduped.take(questionCount).toList();
  }

  /// Lädt statische JSON-Fragen für ein Fach (Fallback).
  Future<QuizData> loadStaticQuizData(String subject) async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/questions/${subject.toLowerCase()}.json',
      );
      return QuizData.fromJson(json.decode(jsonString));
    } catch (e) {
      print('⚠️ Fehler beim Laden der statischen Fragen für $subject: $e');
      return QuizData(subject: subject, questions: []);
    }
  }

  // ── Interne Helfer ────────────────────────────────────────────────────────

  Future<List<Question>> _loadStaticQuestions(String subject, int grade) async {
    try {
      final quizData = await loadStaticQuizData(subject);
      // Etwas mehr laden als nötig damit wir beim Mischen genug haben
      return quizData.getQuestionsForGrade(grade, count: 10);
    } catch (e) {
      return [];
    }
  }
}

// ── Riverpod Providers ────────────────────────────────────────────────────────

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
