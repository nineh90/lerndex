import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/domain/question_model.dart';
import 'ai_quiz_generator_service.dart';

/// 🗄️ AI QUESTION CACHE REPOSITORY
///
/// Verwaltet den Firestore-Cache für KI-generierte Fragen.
///
/// Strategie:
///   - Beim Quiz-Start wird geprüft ob genügend ungespielte Fragen im Cache sind
///   - Wenn < [_refillThreshold] Fragen übrig → neuen Batch generieren (im Hintergrund)
///   - Wenn 0 Fragen übrig → blockierend generieren + sofort zurückgeben
///
/// Firestore-Pfad:
///   users/{userId}/children/{childId}/ai_quiz_cache/{subject}/questions/{questionId}
///
/// Felder pro Frage:
///   question, options[], answer, difficulty, grade, played (bool), createdAt
class AiQuestionCacheRepository {
  final FirebaseFirestore _firestore;
  final AiQuizGeneratorService _generator;

  /// Wenn weniger als [_refillThreshold] Fragen unbeantwortet sind,
  /// wird still im Hintergrund ein neuer Batch generiert.
  static const int _refillThreshold = 5;

  /// Anzahl Fragen die pro Batch generiert werden.
  static const int _batchSize = 10;

  AiQuestionCacheRepository(this._firestore, this._generator);

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Gibt [count] ungespielte Fragen für das Kind zurück.
  ///
  /// - Wenn genug im Cache: sofort aus Firestore
  /// - Wenn zu wenig: erst generieren, dann zurückgeben
  /// - Hintergrund-Refill wenn knapp
  Future<List<Question>> getQuestions({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int count = 5,
  }) async {
    final unplayed = await _loadUnplayed(userId, childId, subject);

    // Zu wenig im Cache → erst generieren
    if (unplayed.length < count) {
      print('🔄 Cache leer für $subject – generiere neue Fragen...');
      await _generateAndCache(
        userId: userId,
        childId: childId,
        child: child,
        subject: subject,
      );
      final fresh = await _loadUnplayed(userId, childId, subject);
      final result = _pickAndMark(fresh, count, userId, childId, subject);
      return result;
    }

    // Hintergrund-Refill wenn knapp
    if (unplayed.length < _refillThreshold) {
      print('🔄 Cache knapp für $subject – generiere im Hintergrund...');
      _generateAndCache(
        userId: userId,
        childId: childId,
        child: child,
        subject: subject,
      ); // kein await → feuert im Hintergrund
    }

    return _pickAndMark(unplayed, count, userId, childId, subject);
  }

  /// Markiert eine Frage als gespielt (nach dem Quiz)
  Future<void> markAsPlayed({
    required String userId,
    required String childId,
    required String subject,
    required String questionId,
  }) async {
    try {
      await _questionsRef(userId, childId, subject).doc(questionId).update({
        'played': true,
        'playedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('⚠️ markAsPlayed Fehler: $e');
    }
  }

  /// Löscht alle gecachten Fragen für ein Kind/Fach (z.B. beim Reset)
  Future<void> clearCache({
    required String userId,
    required String childId,
    required String subject,
  }) async {
    try {
      final snapshot = await _questionsRef(userId, childId, subject).get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('🗑️ Cache gelöscht für $subject');
    } catch (e) {
      print('⚠️ clearCache Fehler: $e');
    }
  }

  // ── Interne Helfer ────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _questionsRef(
    String userId,
    String childId,
    String subject,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('ai_quiz_cache')
        .doc(subject.toLowerCase())
        .collection('questions');
  }

  /// Lädt alle ungespielte Fragen aus dem Cache, älteste zuerst.
  Future<List<_CachedQuestion>> _loadUnplayed(
    String userId,
    String childId,
    String subject,
  ) async {
    try {
      final snapshot = await _questionsRef(
        userId,
        childId,
        subject,
      ).where('played', isEqualTo: false).orderBy('createdAt').get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return _CachedQuestion(
          id: doc.id,
          question: Question(
            grade: data['grade'] as int? ?? 1,
            question: data['question'] as String? ?? '',
            options: List<String>.from(data['options'] ?? []),
            answer: data['answer'] as String? ?? '',
            difficulty: data['difficulty'] as String? ?? 'medium',
          ),
        );
      }).toList();
    } catch (e) {
      print('⚠️ _loadUnplayed Fehler: $e');
      return [];
    }
  }

  /// Holt [count] Fragen aus der Liste und markiert sie als gespielt.
  List<Question> _pickAndMark(
    List<_CachedQuestion> available,
    int count,
    String userId,
    String childId,
    String subject,
  ) {
    available.shuffle();
    final picked = available.take(count).toList();

    // Alle als gespielt markieren (fire-and-forget)
    for (final cq in picked) {
      markAsPlayed(
        userId: userId,
        childId: childId,
        subject: subject,
        questionId: cq.id,
      );
    }

    return picked.map((cq) => cq.question).toList();
  }

  /// Generiert einen neuen Batch via KI und schreibt ihn in den Cache.
  Future<void> _generateAndCache({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
  }) async {
    final questions = await _generator.generateQuestions(
      child: child,
      subject: subject,
      count: _batchSize,
    );

    if (questions.isEmpty) {
      print('⚠️ KI hat keine Fragen zurückgegeben für $subject');
      return;
    }

    // Batch-Write in Firestore
    final batch = _firestore.batch();
    final ref = _questionsRef(userId, childId, subject);

    for (final q in questions) {
      final doc = ref.doc();
      batch.set(doc, {
        'grade': q.grade,
        'question': q.question,
        'options': q.options,
        'answer': q.answer,
        'difficulty': q.difficulty,
        'played': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    print('✅ ${questions.length} Fragen für $subject gecacht');
  }
}

// ── Internes Daten-Hilfsklasse ────────────────────────────────────────────────

class _CachedQuestion {
  final String id;
  final Question question;
  _CachedQuestion({required this.id, required this.question});
}

// ── Provider ─────────────────────────────────────────────────────────────────

final aiQuestionCacheRepositoryProvider = Provider<AiQuestionCacheRepository>((
  ref,
) {
  return AiQuestionCacheRepository(
    FirebaseFirestore.instance,
    ref.watch(aiQuizGeneratorServiceProvider),
  );
});
