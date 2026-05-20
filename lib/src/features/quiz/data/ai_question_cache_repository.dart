import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/domain/question_model.dart';

/// AI QUESTION CACHE REPOSITORY v4
///
/// Strategie:
///   - prefillIfEmpty(): Generiert 10 Fragen NUR wenn Cache leer ist (Pre-Fetch)
///   - getQuestions():   Liefert Fragen aus Cache, Schnell-Batch wenn leer
///   - Hintergrund-Refill: Wenn Vorrat knapp wird, wird nachgeladen
///
/// Fixes in v4:
///   - Race-Condition-Fix: _inflightSubjects verhindert Doppel-Generierung
///     wenn Splash-Screen mehrere Fächer eines Kindes parallel startet.
///   - prefillIfEmpty() macht KEINEN Level-Check mehr — der Level ist beim
///     Splash-Start garantiert aktuell. Level-Checks nur in getQuestions().
///   - _checkAndInvalidateOnLevelChange läuft nie zweimal gleichzeitig für
///     dasselbe childId+subject (ebenfalls durch _inflightSubjects geschützt).
class AiQuestionCacheRepository {
  final FirebaseFirestore _firestore;
  final VertexAIService _generator;

  static const int _refillThreshold = 5;
  static const int _fullBatchSize = 10;
  static const int _quickBatchSize = 2;
  static const int _maxPlayedToKeep = 100;

  /// Schema-Version für Cache-Einträge. Wird beim Schreiben in jedes Dokument
  /// abgelegt. Wenn beim Lesen eine ältere Version gefunden wird, wird der
  /// Cache invalidiert.
  ///
  /// Versionen:
  /// - 1 (default für alle Pre-Update-Einträge): Kein emoji-Feld
  /// - 2: Mit emoji-Feld (Whitelist von SafeEmojis)
  static const int _cacheSchemaVersion = 2;

  /// In-Memory-Guard: verhindert Race Conditions beim parallelen Prefetch.
  /// Key: "$childId|$subject"
  final Set<String> _inflightSubjects = {};

  AiQuestionCacheRepository(this._firestore, this._generator);

  // ================================================================
  // OEFFENTLICHE API
  // ================================================================

  /// Fuellt den Cache fuer ein Fach, WENN er leer oder zu knapp ist.
  /// Blockiert bis die Generierung fertig ist.
  /// Wird beim Splash-Screen-Prefetch aufgerufen.
  ///
  /// KEIN Level-Check hier — beim Splash-Start ist child.level aktuell.
  /// Race-Condition-Schutz: Wenn dasselbe childId+subject bereits läuft,
  /// wird dieser Aufruf sofort übersprungen (kein Doppel-Request).
  Future<void> prefillIfEmpty({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
  }) async {
    final key = '$childId|$subject';

    // Guard: Bereits in Bearbeitung → überspringen
    if (_inflightSubjects.contains(key)) {
      debugPrint(
        '⏭️ Pre-Fill: $subject für ${child.name} läuft bereits – überspringe',
      );
      return;
    }

    _inflightSubjects.add(key);
    try {
      // Prüfen ob schon genug ungespielte Fragen für das aktuelle Level da sind
      final unplayed = await _loadUnplayedForLevel(
        userId,
        childId,
        subject,
        child.level,
      );

      if (unplayed.length >= _refillThreshold) {
        debugPrint(
          '✅ Pre-Fill: $subject hat schon ${unplayed.length} Fragen '
          '(Level ${child.level}) – kein Prefetch nötig',
        );
        return;
      }

      debugPrint(
        '🔮 Pre-Fill: ${unplayed.length}/$_refillThreshold Fragen für $subject '
        '(Level ${child.level}) – generiere $_fullBatchSize neue...',
      );
      final recentTopics = await _loadRecentTopics(userId, childId, subject);

      final questions = await _generator.generateQuizQuestions(
        child: child,
        subject: subject,
        count: _fullBatchSize,
        recentTopics: recentTopics,
      );

      if (questions.isNotEmpty) {
        await _writeToCache(userId, childId, child, subject, questions);
        debugPrint(
          '✅ Pre-Fill: ${questions.length} Fragen für $subject bereit',
        );
      } else {
        debugPrint('⚠️ Pre-Fill: Keine Fragen für $subject generiert');
      }
    } catch (e) {
      debugPrint('⚠️ Pre-Fill Fehler für $subject: $e');
    } finally {
      _inflightSubjects.remove(key);
    }
  }

  /// Gibt [count] ungespielte Fragen zurück.
  /// Wenn Cache voll: Sofort aus Firestore (0 Wartezeit).
  /// Wenn Cache leer: Schnell-Batch (~1-2s).
  ///
  /// Level-Check läuft hier (nicht in prefillIfEmpty) da getQuestions()
  /// auch nach einem Level-Up mitten im Tag aufgerufen wird.
  Future<List<Question>> getQuestions({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int count = 5,
  }) async {
    // Level-Check NUR in getQuestions – prefillIfEmpty vertraut dem aktuellen Level
    await _checkAndInvalidateOnLevelChange(userId, childId, child, subject);
    await _checkAndInvalidateOnSchemaChange(userId, childId, subject);

    final unplayed = await _loadUnplayed(userId, childId, subject);

    // Genug vorhanden → sofort liefern
    if (unplayed.length >= count) {
      if (unplayed.length - count < _refillThreshold) {
        _backgroundRefill(userId, childId, child, subject);
      }
      return _pickAndMark(unplayed, count, userId, childId, subject);
    }

    // Nicht genug: Schnell-Batch synchron generieren
    debugPrint(
      '🚀 Schnell-Batch: Generiere $_quickBatchSize Fragen für $subject...',
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
      debugPrint('⚠️ markAsPlayed Fehler: $e');
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
      debugPrint('🗑️ Cache gelöscht für $subject');
    } catch (e) {
      debugPrint('⚠️ clearCache Fehler: $e');
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

  /// Invalidiert den Cache wenn das Level des Kindes gestiegen ist.
  /// Wird NUR in getQuestions() aufgerufen, nicht in prefillIfEmpty().
  Future<void> _checkAndInvalidateOnLevelChange(
    String userId,
    String childId,
    ChildModel child,
    String subject,
  ) async {
    try {
      final metaDoc = await _cacheMetaRef(userId, childId, subject).get();
      if (!metaDoc.exists) return; // Kein Cache → nichts zu invalidieren

      final cachedLevel = metaDoc.data()?['generatedForLevel'] as int?;
      if (cachedLevel != null && cachedLevel != child.level) {
        debugPrint(
          '🔄 Level geändert ($cachedLevel → ${child.level}) '
          '– Cache für $subject invalidiert',
        );
        await clearCache(userId: userId, childId: childId, subject: subject);
      }
    } catch (e) {
      debugPrint('⚠️ Level-Check Fehler: $e');
    }
  }

  /// Invalidiert den Cache wenn dort noch Pre-Emoji-Einträge (Schema v1)
  /// liegen. Greift einmalig nach App-Update auf v2 — danach steht in der
  /// Meta-Doc `schemaVersion: 2` und der Check ist no-op.
  Future<void> _checkAndInvalidateOnSchemaChange(
    String userId,
    String childId,
    String subject,
  ) async {
    try {
      final metaDoc = await _cacheMetaRef(userId, childId, subject).get();
      if (!metaDoc.exists) return;

      final cachedSchema =
          metaDoc.data()?['schemaVersion'] as int? ?? 1; // null = v1 (alt)
      if (cachedSchema < _cacheSchemaVersion) {
        debugPrint(
          '🔄 Cache-Schema veraltet (v$cachedSchema → v$_cacheSchemaVersion) '
          '– Cache für $subject invalidiert (Emoji-Migration)',
        );
        await clearCache(userId: userId, childId: childId, subject: subject);
      }
    } catch (e) {
      debugPrint('⚠️ Schema-Check Fehler: $e');
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
        'schemaVersion': _cacheSchemaVersion,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // -- Laden --

  /// Lädt alle ungespielten Fragen unabhängig vom Level.
  /// Wird in getQuestions() verwendet (nach Level-Check).
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
            emoji: data['emoji'] as String?,
          ),
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ _loadUnplayed Fehler: $e');
      return [];
    }
  }

  /// Lädt ungespielte Fragen NUR für ein bestimmtes Level.
  /// Wird in prefillIfEmpty() verwendet um festzustellen ob genug
  /// level-passende Fragen da sind, ohne den Cache zu invalidieren.
  Future<List<_CachedQuestion>> _loadUnplayedForLevel(
    String userId,
    String childId,
    String subject,
    int level,
  ) async {
    try {
      final snapshot = await _questionsRef(userId, childId, subject)
          .where('played', isEqualTo: false)
          .where('generatedForLevel', isEqualTo: level)
          .orderBy('createdAt')
          .get();

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
            emoji: data['emoji'] as String?,
          ),
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ _loadUnplayedForLevel Fehler: $e');
      // Fallback: alle ungespielten laden
      return _loadUnplayed(userId, childId, subject);
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
    final key = '$childId|$subject|bg';
    if (_inflightSubjects.contains(key)) return;
    _inflightSubjects.add(key);

    try {
      final recentTopics = await _loadRecentTopics(userId, childId, subject);

      final questions = await _generator.generateQuizQuestions(
        child: child,
        subject: subject,
        count: count,
        recentTopics: recentTopics,
      );

      if (questions.isEmpty) return;

      // Duplikat-Prüfung gegen bereits gecachte Fragen
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
      debugPrint('⚠️ Hintergrund-Generierung Fehler: $e');
    } finally {
      _inflightSubjects.remove(key);
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
        if (q.emoji != null) 'emoji': q.emoji,
        'played': false,
        'createdAt': FieldValue.serverTimestamp(),
        'generatedForLevel': child.level,
        // Schema-Version. Wird in _checkAndInvalidateOnSchemaChange genutzt
        // um alte Cache-Einträge (vor Emoji-Support) automatisch zu löschen.
        'schemaVersion': _cacheSchemaVersion,
      });
    }

    await batch.commit();
    await _updateCacheMeta(userId, childId, subject, child.level);
    debugPrint(
      '✅ ${questions.length} Fragen für $subject gecacht (Level ${child.level})',
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
      debugPrint('🧹 ${toDelete.length} alte Fragen aufgeräumt');
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
