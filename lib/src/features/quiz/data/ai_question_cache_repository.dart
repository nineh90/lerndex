import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex1/src/ai/vertex_ai_service.dart';
import 'package:lerndex1/src/features/auth/domain/child_model.dart';
import 'package:lerndex1/src/features/quiz/domain/question_model.dart';

/// AI QUESTION CACHE REPOSITORY v3
///
/// Strategie:
///   - prefillIfEmpty(): Generiert 10 Fragen NUR wenn Cache leer ist (fuer Pre-Fetch)
///   - getQuestions(): Liefert Fragen aus Cache, generiert Schnell-Batch wenn leer
///   - Hintergrund-Refill: Wenn Vorrat knapp wird, wird nachgeladen
///
/// Pre-Fetch Flow (bei Kind-Erstellung):
///   1. prefillIfEmpty("Mathe") -> Generiert 10 Fragen, cached in Firestore
///   2. prefillIfEmpty("Deutsch") -> Generiert 10 Fragen
///   3. ... weitere Faecher
///   -> Kind hat beim ersten Login sofort Fragen
///
/// Quiz Flow (Kind spielt):
///   1. getQuestions() -> Liest aus Cache (sofort!)
///   2. Wenig uebrig? -> Hintergrund-Refill, Kind merkt nichts
///   3. Cache leer (sollte nicht passieren)? -> Schnell-Batch von 2 Fragen
class AiQuestionCacheRepository {
  final FirebaseFirestore _firestore;
  final VertexAIService _generator;

  static const int _refillThreshold = 5;
  static const int _fullBatchSize = 10;
  static const int _quickBatchSize = 2;
  static const int _maxPlayedToKeep = 100;

  AiQuestionCacheRepository(this._firestore, this._generator);

  // ================================================================
  // OEFFENTLICHE API
  // ================================================================

  /// Fuellt den Cache fuer ein Fach, WENN er leer ist.
  /// Blockiert bis die Generierung fertig ist.
  /// Wird beim Pre-Fetch (Kind-Erstellung) aufgerufen.
  ///
  /// Unterschied zu getQuestions():
  /// - Gibt keine Fragen zurueck (nur Caching)
  /// - Markiert keine Fragen als gespielt
  /// - Generiert immer einen vollen Batch (_fullBatchSize)
  /// - Ueberspringt wenn schon genug im Cache sind
  Future<void> prefillIfEmpty({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
  }) async {
    try {
      // Pruefen ob schon genug da sind
      final unplayed = await _loadUnplayed(userId, childId, subject);
      if (unplayed.length >= _refillThreshold) {
        print('✅ Pre-Fill: $subject hat schon ${unplayed.length} Fragen');
        return;
      }

      print('🔮 Pre-Fill: Generiere $_fullBatchSize Fragen fuer $subject...');
      final recentTopics = await _loadRecentTopics(userId, childId, subject);

      final questions = await _generator.generateQuizQuestions(
        child: child,
        subject: subject,
        count: _fullBatchSize,
        recentTopics: recentTopics,
      );

      if (questions.isNotEmpty) {
        await _writeToCache(userId, childId, child, subject, questions);
        print('✅ Pre-Fill: ${questions.length} Fragen fuer $subject bereit');
      } else {
        print('⚠️ Pre-Fill: Keine Fragen fuer $subject generiert');
      }
    } catch (e) {
      print('⚠️ Pre-Fill Fehler fuer $subject: $e');
    }
  }

  /// Gibt [count] ungespielte Fragen zurueck.
  /// Wenn Cache voll: Sofort aus Firestore (0 Wartezeit).
  /// Wenn Cache leer: Schnell-Batch (2 Fragen, ~1-2s).
  Future<List<Question>> getQuestions({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int count = 5,
  }) async {
    await _checkAndInvalidateOnLevelChange(userId, childId, child, subject);

    final unplayed = await _loadUnplayed(userId, childId, subject);

    // Genuegend vorhanden -> sofort liefern
    if (unplayed.length >= count) {
      if (unplayed.length - count < _refillThreshold) {
        _backgroundRefill(userId, childId, child, subject);
      }
      return _pickAndMark(unplayed, count, userId, childId, subject);
    }

    // Nicht genug: Schnell-Batch generieren
    print(
      '🚀 Schnell-Batch: Generiere $_quickBatchSize Fragen fuer $subject...',
    );
    final recentTopics = await _loadRecentTopics(userId, childId, subject);

    final quickQuestions = await _generator.generateQuizQuestions(
      child: child,
      subject: subject,
      count: _quickBatchSize,
      recentTopics: recentTopics,
    );

    if (quickQuestions.isNotEmpty) {
      await _writeToCache(userId, childId, child, subject, quickQuestions);
    }

    // Rest im Hintergrund nachladen
    _generateInBackground(
      userId: userId,
      childId: childId,
      child: child,
      subject: subject,
      count: _fullBatchSize,
    );

    final allAvailable = await _loadUnplayed(userId, childId, subject);
    if (allAvailable.isEmpty) return [];
    return _pickAndMark(allAvailable, count, userId, childId, subject);
  }

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
      try {
        await _cacheMetaRef(userId, childId, subject).delete();
      } catch (_) {}
      print('🗑️ Cache geloescht fuer $subject');
    } catch (e) {
      print('⚠️ clearCache Fehler: $e');
    }
  }

  // ================================================================
  // INTERNE HELFER
  // ================================================================

  CollectionReference<Map<String, dynamic>> _questionsRef(
    String userId,
    String childId,
    String subject,
  ) => _firestore
      .collection('users')
      .doc(userId)
      .collection('children')
      .doc(childId)
      .collection('ai_quiz_cache')
      .doc(subject.toLowerCase())
      .collection('questions');

  DocumentReference<Map<String, dynamic>> _cacheMetaRef(
    String userId,
    String childId,
    String subject,
  ) => _firestore
      .collection('users')
      .doc(userId)
      .collection('children')
      .doc(childId)
      .collection('ai_quiz_cache')
      .doc(subject.toLowerCase());

  // -- Level-Change Detection --

  Future<void> _checkAndInvalidateOnLevelChange(
    String userId,
    String childId,
    ChildModel child,
    String subject,
  ) async {
    try {
      final metaDoc = await _cacheMetaRef(userId, childId, subject).get();
      if (metaDoc.exists) {
        final cachedLevel = metaDoc.data()?['generatedForLevel'] as int?;
        if (cachedLevel != null && cachedLevel != child.level) {
          print(
            '🔄 Level geaendert ($cachedLevel -> ${child.level}) - Cache invalidiert',
          );
          await clearCache(userId: userId, childId: childId, subject: subject);
        }
      }
    } catch (e) {
      print('⚠️ Level-Check Fehler: $e');
    }
  }

  Future<void> _updateCacheMeta(
    String userId,
    String childId,
    String subject,
    int level,
  ) async {
    try {
      await _cacheMetaRef(userId, childId, subject).set({
        'generatedForLevel': level,
        'lastRefill': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // -- Laden --

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
            topic: data['topic'] as String? ?? '',
          ),
        );
      }).toList();
    } catch (e) {
      print('⚠️ _loadUnplayed Fehler: $e');
      return [];
    }
  }

  Future<List<String>> _loadRecentTopics(
    String userId,
    String childId,
    String subject,
  ) async {
    try {
      final snapshot = await _questionsRef(
        userId,
        childId,
        subject,
      ).orderBy('createdAt', descending: true).limit(30).get();

      final topics = <String>{};
      for (final doc in snapshot.docs) {
        final topic = doc.data()['topic'] as String?;
        if (topic != null && topic.isNotEmpty) {
          topics.add(topic);
        }
      }
      return topics.toList();
    } catch (e) {
      return [];
    }
  }

  // -- Pick & Mark --

  List<Question> _pickAndMark(
    List<_CachedQuestion> available,
    int count,
    String userId,
    String childId,
    String subject,
  ) {
    available.shuffle();
    final picked = available.take(count).toList();

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

  // -- Hintergrund-Generierung --

  void _backgroundRefill(
    String userId,
    String childId,
    ChildModel child,
    String subject,
  ) {
    _generateInBackground(
      userId: userId,
      childId: childId,
      child: child,
      subject: subject,
      count: _fullBatchSize,
    );
  }

  Future<void> _generateInBackground({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    required int count,
  }) async {
    try {
      final recentTopics = await _loadRecentTopics(userId, childId, subject);

      final questions = await _generator.generateQuizQuestions(
        child: child,
        subject: subject,
        count: count,
        recentTopics: recentTopics,
      );

      if (questions.isEmpty) return;

      // Duplikat-Pruefung gegen ungespielte im Cache
      final existing = await _loadUnplayed(userId, childId, subject);
      final existingTexts = existing
          .map((cq) => cq.question.question.toLowerCase().trim())
          .toSet();

      final unique = questions
          .where(
            (q) => !existingTexts.contains(q.question.toLowerCase().trim()),
          )
          .toList();

      if (unique.isNotEmpty) {
        await _writeToCache(userId, childId, child, subject, unique);
      }

      await _cleanupOldPlayed(userId, childId, subject);
    } catch (e) {
      print('⚠️ Hintergrund-Generierung Fehler: $e');
    }
  }

  Future<void> _writeToCache(
    String userId,
    String childId,
    ChildModel child,
    String subject,
    List<Question> questions,
  ) async {
    final batch = _firestore.batch();
    final ref = _questionsRef(userId, childId, subject);

    for (final q in questions) {
      batch.set(ref.doc(), {
        'grade': q.grade,
        'question': q.question,
        'options': q.options,
        'answer': q.answer,
        'difficulty': q.difficulty,
        'topic': q.topic,
        'played': false,
        'createdAt': FieldValue.serverTimestamp(),
        'generatedForLevel': child.level,
      });
    }

    await batch.commit();
    await _updateCacheMeta(userId, childId, subject, child.level);
    print(
      '✅ ${questions.length} Fragen fuer $subject gecacht (Level ${child.level})',
    );
  }

  Future<void> _cleanupOldPlayed(
    String userId,
    String childId,
    String subject,
  ) async {
    try {
      final snapshot = await _questionsRef(userId, childId, subject)
          .where('played', isEqualTo: true)
          .orderBy('playedAt', descending: true)
          .get();

      if (snapshot.docs.length <= _maxPlayedToKeep) return;

      final toDelete = snapshot.docs.sublist(_maxPlayedToKeep);
      final batch = _firestore.batch();
      for (final doc in toDelete) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('🧹 ${toDelete.length} alte Fragen aufgeraeumt');
    } catch (_) {}
  }
}

class _CachedQuestion {
  final String id;
  final Question question;
  _CachedQuestion({required this.id, required this.question});
}

final aiQuestionCacheRepositoryProvider = Provider<AiQuestionCacheRepository>((
  ref,
) {
  return AiQuestionCacheRepository(
    FirebaseFirestore.instance,
    ref.watch(vertexAIServiceProvider),
  );
});
