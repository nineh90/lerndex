import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/data/curriculum_data.dart';
import 'package:lerndex/src/features/quiz/domain/question_model.dart';

/// Was mit dem Quiz-Cache eines Fachs passieren muss, bevor er genutzt wird.
enum CacheAction {
  /// Fragen passen weiter.
  keep,

  /// Andere Lehrplanstufe: ungespielte Fragen verwerfen. Gespielte bleiben
  /// (Schutz gegen Wiederholung).
  discardUnplayed,

  /// Altes Format (vor Emoji-Feld): alles löschen.
  clearAll,
}

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
///
/// Seit v5:
///   - Ein Levelaufstieg verwirft den Cache nur, wenn sich die Lehrplanstufe
///     ändert ([CurriculumData.curriculumStage]), und dann nur die
///     ungespielten Fragen – die gespielten schützen weiter vor Wiederholung.
///   - Das Meta-Dokument wird pro Abruf einmal gelesen (Stufe + Schema).
///   - _inflightSubjects gilt für alle Instanzen (static): auch ein Aufrufer
///     mit eigener Instanz löst keine doppelte Generierung aus.
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
  /// Key: "$childId|$subject". Für alle Instanzen gemeinsam.
  static final Set<String> _inflightSubjects = {};

  AiQuestionCacheRepository(this._firestore, this._generator);

  // ================================================================
  // OEFFENTLICHE API
  // ================================================================

  /// Fuellt den Cache fuer ein Fach, WENN er leer oder zu knapp ist.
  /// Blockiert bis die Generierung fertig ist.
  /// Wird beim Splash-Screen-Prefetch aufgerufen.
  ///
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
      // Fragen einer anderen Lehrplanstufe zählen nicht
      await _ensureCacheCurrent(userId, childId, child, subject);
      final unplayed = await _loadUnplayed(userId, childId, subject);

      if (unplayed.length >= _refillThreshold) {
        debugPrint(
          '✅ Pre-Fill: $subject hat schon ${unplayed.length} Fragen '
          '(Level ${child.level}) – kein Prefetch nötig',
        );
        return;
      }

      debugPrint(
        '🔮 Pre-Fill: ${unplayed.length}/$_refillThreshold Fragen für $subject '
        '(Level ${child.level}) – generiere $_fullBatchSize neue…',
      );
      final recent = await _loadRecentContext(userId, childId, subject);

      final questions = await _generator.generateQuizQuestions(
        child: child,
        subject: subject,
        count: _fullBatchSize,
        recentTopics: recent.topics,
        recentQuestions: recent.questions,
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
  /// Wenn Cache leer: Schnell-Batch (~5-8s mit gemini-3.5-flash).
  ///
  /// Prüft vorher die Lehrplanstufe – getQuestions() läuft auch nach einem
  /// Level-Up mitten im Tag.
  Future<List<Question>> getQuestions({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    int count = 5,
  }) async {
    await _ensureCacheCurrent(userId, childId, child, subject);

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
      '🚀 Schnell-Batch: Generiere $_quickBatchSize Fragen für $subject…',
    );
    final recent = await _loadRecentContext(userId, childId, subject);

    final quickQuestions = await _generator.generateQuizQuestions(
      child: child,
      subject: subject,
      count: _quickBatchSize,
      recentTopics: recent.topics,
      recentQuestions: recent.questions,
    );

    if (quickQuestions.isNotEmpty) {
      await _writeToCache(userId, childId, child, subject, quickQuestions);
    }

    // Rest im Hintergrund nachladen – außer der Start-Prefetch füllt dieses
    // Fach gerade ohnehin (sonst würden doppelt Fragen generiert).
    if (!_inflightSubjects.contains('$childId|$subject')) {
      _generateInBackground(
        userId: userId,
        childId: childId,
        child: child,
        subject: subject,
        count: _fullBatchSize,
      );
    }

    final allAvailable = await _loadUnplayed(userId, childId, subject);
    if (allAvailable.isEmpty) return [];
    return _pickAndMark(allAvailable, count, userId, childId, subject);
  }

  /// Speist Aufgaben, die aus einem Tutor-Gespräch abgeleitet wurden, in den
  /// Quiz-Cache des passenden Fachs ein. Generiert [count] themenpassende
  /// Aufgaben (gesteuert über [focusHint]) und schreibt nur Nicht-Duplikate.
  ///
  /// [subject] muss der Quiz-Fach-Schlüssel sein (z.B. 'mathe', 'deutsch').
  /// Läuft im Hintergrund (fire-and-forget aus dem Tutor) und ist gegen
  /// Doppel-Aufrufe via [_inflightSubjects] geschützt.
  Future<void> injectTutorQuestions({
    required String userId,
    required String childId,
    required ChildModel child,
    required String subject,
    required String focusHint,
    int count = 3,
  }) async {
    final key = '$childId|$subject|tutor';
    if (_inflightSubjects.contains(key)) return;
    _inflightSubjects.add(key);

    try {
      final recent = await _loadRecentContext(userId, childId, subject);

      final questions = await _generator.generateQuizQuestions(
        child: child,
        subject: subject,
        count: count,
        recentTopics: recent.topics,
        recentQuestions: recent.questions,
        focusHint: focusHint,
      );

      if (questions.isEmpty) {
        debugPrint('⚠️ injectTutorQuestions: keine Aufgaben für $subject');
        return;
      }

      // Duplikat-Prüfung gegen bereits gecachte (ungespielte) Fragen
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
        debugPrint(
          '🎓 ${unique.length} Tutor-Aufgaben in Quiz-Cache ($subject) eingespeist',
        );
      }
    } catch (e) {
      debugPrint('⚠️ injectTutorQuestions Fehler: $e');
    } finally {
      _inflightSubjects.remove(key);
    }
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

  // -- Stufen- und Schema-Prüfung --

  /// Entscheidet anhand des Meta-Dokuments, ob der Cache noch passt.
  /// Alte Meta-Dokumente ohne `curriculumStage` werden über
  /// `generatedForLevel` mit der heutigen Schulform/Klasse verglichen.
  @visibleForTesting
  static CacheAction cacheActionFor(
    Map<String, dynamic>? meta,
    ChildModel child,
  ) {
    if (meta == null) return CacheAction.keep; // Kein Cache
    final schema = meta['schemaVersion'] as int? ?? 1; // null = v1 (alt)
    if (schema < _cacheSchemaVersion) return CacheAction.clearAll;

    final current = CurriculumData.curriculumStage(
      schoolType: child.schoolType,
      grade: child.grade,
      level: child.level,
    );
    var cached = meta['curriculumStage'] as String?;
    if (cached == null) {
      final level = meta['generatedForLevel'] as int?;
      if (level == null) return CacheAction.keep;
      cached = CurriculumData.curriculumStage(
        schoolType: child.schoolType,
        grade: child.grade,
        level: level,
      );
    }
    return cached == current ? CacheAction.keep : CacheAction.discardUnplayed;
  }

  /// Ein Read aufs Meta-Dokument; verwirft bei Bedarf Fragen.
  Future<void> _ensureCacheCurrent(
    String userId,
    String childId,
    ChildModel child,
    String subject,
  ) async {
    try {
      final metaDoc = await _cacheMetaRef(userId, childId, subject).get();
      switch (cacheActionFor(metaDoc.data(), child)) {
        case CacheAction.keep:
          return;
        case CacheAction.clearAll:
          debugPrint('🔄 Cache-Schema veraltet – Cache für $subject gelöscht');
          await clearCache(userId: userId, childId: childId, subject: subject);
        case CacheAction.discardUnplayed:
          debugPrint(
            '🔄 Neue Lehrplanstufe – ungespielte Fragen für $subject verworfen',
          );
          await _discardUnplayed(userId, childId, subject);
      }
    } catch (e) {
      debugPrint('⚠️ Cache-Prüfung Fehler: $e');
    }
  }

  /// Löscht nur die ungespielten Fragen eines Fachs.
  Future<void> _discardUnplayed(
    String userId,
    String childId,
    String subject,
  ) async {
    final snapshot = await _questionsRef(
      userId,
      childId,
      subject,
    ).where('played', isEqualTo: false).get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> _updateCacheMeta(
    String userId,
    String childId,
    String subject,
    ChildModel child,
  ) async {
    try {
      await _cacheMetaRef(userId, childId, subject).set({
        'generatedForLevel': child.level,
        'curriculumStage': CurriculumData.curriculumStage(
          schoolType: child.schoolType,
          grade: child.grade,
          level: child.level,
        ),
        'lastRefill': FieldValue.serverTimestamp(),
        'schemaVersion': _cacheSchemaVersion,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // -- Laden --

  /// Lädt alle ungespielten Fragen (nach der Stufen-Prüfung).
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

  /// Lädt in EINEM Read den jüngsten Quiz-Kontext für die Anti-Wiederholungs-
  /// Hinweise an die KI: die zuletzt abgefragten Unterthemen UND die zuletzt
  /// gestellten Fragetexte (damit neue Batches inhaltlich nicht doppeln).
  Future<({List<String> topics, List<String> questions})> _loadRecentContext(
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
      final questions = <String>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final topic = data['topic'] as String?;
        if (topic != null && topic.isNotEmpty) {
          topics.add(topic);
        }
        final question = data['question'] as String?;
        if (question != null &&
            question.trim().isNotEmpty &&
            questions.length < 20) {
          questions.add(question.trim());
        }
      }
      return (topics: topics.toList(), questions: questions);
    } catch (e) {
      return (topics: const <String>[], questions: const <String>[]);
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
      final recent = await _loadRecentContext(userId, childId, subject);

      final questions = await _generator.generateQuizQuestions(
        child: child,
        subject: subject,
        count: count,
        recentTopics: recent.topics,
        recentQuestions: recent.questions,
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
    await _updateCacheMeta(userId, childId, subject, child);
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
