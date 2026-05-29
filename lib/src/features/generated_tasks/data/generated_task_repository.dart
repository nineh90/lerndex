import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'generated_task_models.dart';
import 'approved_questions_params.dart';

/// 🗄️ REPOSITORY FÜR GENERIERTE AUFGABEN
/// Verwaltet das Speichern, Laden und Freigeben von KI-generierten Aufgaben
class GeneratedTaskRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ========================================================================
  // AUFGABEN SPEICHERN
  // ========================================================================

  /// Speichert einen neuen Batch von generierten Aufgaben
  Future<String> saveGeneratedBatch({
    required String userId,
    required String childId,
    required String childName,
    required Subject subject,
    required String imageUrl,
    required List<GeneratedQuestion> questions,
  }) async {
    try {
      // Batch-Dokument erstellen
      final batchDoc = _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc();

      final batch = _firestore.batch();

      // Hauptdokument (inkl. Zähler-Felder für Live-Stream)
      batch.set(batchDoc, {
        'childId': childId,
        'childName': childName,
        'subject': subject.value,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'totalTasks': questions.length,
        'pendingTasks': questions.length,
        'approvedTasks': 0,
        'rejectedTasks': 0,
      });

      // Einzelne Fragen als Sub-Collection
      for (var question in questions) {
        final questionDoc = batchDoc.collection('questions').doc();
        batch.set(questionDoc, question.toFirestore());
      }

      await batch.commit();
      debugPrint(
        '✅ Batch gespeichert: ${batchDoc.id} mit ${questions.length} Aufgaben',
      );

      return batchDoc.id;
    } catch (e) {
      debugPrint('❌ Fehler beim Speichern des Batches: $e');
      rethrow;
    }
  }

  // ========================================================================
  // AUFGABEN LADEN
  // ========================================================================

  /// Lädt alle Batches für einen User (für Eltern-Dashboard)
  /// Zähler werden direkt aus dem Batch-Dokument gelesen → echter Live-Stream
  Stream<List<GeneratedTaskBatch>> watchBatchesForUser(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('generated_batches')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final batches = <GeneratedTaskBatch>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final migrated = await _migrateCountersIfNeeded(doc, data, userId);
            batches.add(
              GeneratedTaskBatch.fromFirestore(migrated ?? doc, const []),
            );
          }
          return batches;
        });
  }

  /// Lädt alle ausstehenden Batches (mit pending-Aufgaben)
  Stream<List<GeneratedTaskBatch>> watchPendingBatches(String userId) {
    return watchBatchesForUser(userId).map((batches) {
      return batches.where((batch) => batch.pendingTasks > 0).toList();
    });
  }

  /// Lädt alle Batches für einen User gefiltert nach Kind
  /// Zähler werden direkt aus dem Batch-Dokument gelesen → echter Live-Stream
  Stream<List<GeneratedTaskBatch>> watchBatchesForChild(
    String userId,
    String childId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('generated_batches')
        .where('childId', isEqualTo: childId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final batches = <GeneratedTaskBatch>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final migrated = await _migrateCountersIfNeeded(doc, data, userId);
            batches.add(
              GeneratedTaskBatch.fromFirestore(migrated ?? doc, const []),
            );
          }
          return batches;
        });
  }

  /// Migriert alte Batches ohne Zähler-Felder einmalig.
  /// Gibt das aktualisierte Dokument zurück, oder null wenn keine Migration nötig war.
  Future<DocumentSnapshot?> _migrateCountersIfNeeded(
    DocumentSnapshot doc,
    Map<String, dynamic> data,
    String userId,
  ) async {
    final hasCounters =
        data.containsKey('pendingTasks') &&
        data.containsKey('approvedTasks') &&
        data.containsKey('rejectedTasks');

    if (hasCounters) return null; // Nichts zu tun

    // Fragen einmalig laden um echte Zähler zu ermitteln
    final questionsSnapshot = await doc.reference.collection('questions').get();
    int pending = 0, approved = 0, rejected = 0;
    for (final q in questionsSnapshot.docs) {
      final status = (q.data())['status'] ?? 'pending';
      if (status == 'approved') {
        approved++;
      } else if (status == 'rejected') {
        rejected++;
      } else {
        pending++;
      }
    }

    // Schreibe Zähler ins Dokument
    await doc.reference.update({
      'pendingTasks': pending,
      'approvedTasks': approved,
      'rejectedTasks': rejected,
    });

    // Frisch geladenes Dokument zurückgeben
    return doc.reference.get();
  }

  /// Stream für Live-Fragen eines einzelnen Batches
  Stream<List<GeneratedQuestion>> watchQuestionsForBatch(
    String userId,
    String batchId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('generated_batches')
        .doc(batchId)
        .collection('questions')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GeneratedQuestion.fromFirestore(doc))
              .toList(),
        );
  }

  /// Pending task count für ein spezifisches Kind
  Stream<int> watchPendingTaskCountForChild(String userId, String childId) {
    return watchBatchesForChild(userId, childId).map((batches) {
      return batches.fold<int>(0, (acc, batch) => acc + batch.pendingTasks);
    });
  }

  /// Lädt einen einzelnen Batch mit allen Details
  Future<GeneratedTaskBatch?> getBatch(String userId, String batchId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId)
          .get();

      if (!doc.exists) return null;

      final questionsSnapshot = await doc.reference
          .collection('questions')
          .get();
      final questions = questionsSnapshot.docs
          .map((qDoc) => GeneratedQuestion.fromFirestore(qDoc))
          .toList();

      return GeneratedTaskBatch.fromFirestore(doc, questions);
    } catch (e) {
      debugPrint('❌ Fehler beim Laden des Batches: $e');
      return null;
    }
  }

  /// Lädt alle freigegebenen Aufgaben für ein Kind in einem Fach
  Future<List<GeneratedQuestion>> getApprovedQuestionsForChild({
    required String userId,
    required String childId,
    required Subject subject,
  }) async {
    try {
      // Lade alle Batches für dieses Kind und Fach
      final batchesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .where('childId', isEqualTo: childId)
          .where('subject', isEqualTo: subject.value)
          .get();

      final approvedQuestions = <GeneratedQuestion>[];

      // Durchsuche alle Batches nach freigegebenen Aufgaben
      for (var batchDoc in batchesSnapshot.docs) {
        final questionsSnapshot = await batchDoc.reference
            .collection('questions')
            .where('status', isEqualTo: 'approved')
            .get();

        approvedQuestions.addAll(
          questionsSnapshot.docs.map((q) => GeneratedQuestion.fromFirestore(q)),
        );
      }

      debugPrint(
        '✅ ${approvedQuestions.length} freigegebene Aufgaben geladen für ${subject.displayName}',
      );
      return approvedQuestions;
    } catch (e) {
      debugPrint('❌ Fehler beim Laden freigegebener Aufgaben: $e');
      return [];
    }
  }

  // ========================================================================
  // FREIGABE-LOGIK
  // ========================================================================

  /// Gibt eine Aufgabe frei (approve)
  Future<void> approveQuestion({
    required String userId,
    required String batchId,
    required String questionId,
    required String approvedByUserId,
    bool wasPending = true,
  }) async {
    try {
      final batchRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId);

      final firestoreBatch = _firestore.batch();

      // Frage updaten
      firestoreBatch.update(batchRef.collection('questions').doc(questionId), {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': approvedByUserId,
      });

      // Zähler im Batch-Dokument atomar anpassen
      if (wasPending) {
        firestoreBatch.update(batchRef, {
          'approvedTasks': FieldValue.increment(1),
          'pendingTasks': FieldValue.increment(-1),
        });
      }

      await firestoreBatch.commit();
      debugPrint('✅ Aufgabe freigegeben: $questionId');
    } catch (e) {
      debugPrint('❌ Fehler beim Freigeben: $e');
      rethrow;
    }
  }

  /// Lehnt eine Aufgabe ab (reject)
  Future<void> rejectQuestion({
    required String userId,
    required String batchId,
    required String questionId,
    String? reason,
    bool wasPending = true,
  }) async {
    try {
      final batchRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId);

      final firestoreBatch = _firestore.batch();

      // Frage updaten
      firestoreBatch.update(batchRef.collection('questions').doc(questionId), {
        'status': 'rejected',
        'rejectionReason': reason,
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // Zähler im Batch-Dokument atomar anpassen
      if (wasPending) {
        firestoreBatch.update(batchRef, {
          'rejectedTasks': FieldValue.increment(1),
          'pendingTasks': FieldValue.increment(-1),
        });
      }

      await firestoreBatch.commit();
      debugPrint('✅ Aufgabe abgelehnt: $questionId');
    } catch (e) {
      debugPrint('❌ Fehler beim Ablehnen: $e');
      rethrow;
    }
  }

  /// Gibt alle ausstehenden Aufgaben in einem Batch frei
  Future<void> approveAllPendingInBatch({
    required String userId,
    required String batchId,
    required String approvedByUserId,
  }) async {
    try {
      final batchRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId);

      final questionsSnapshot = await batchRef
          .collection('questions')
          .where('status', isEqualTo: 'pending')
          .get();

      final pendingCount = questionsSnapshot.docs.length;
      if (pendingCount == 0) return;

      final firestoreBatch = _firestore.batch();

      for (var doc in questionsSnapshot.docs) {
        firestoreBatch.update(doc.reference, {
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': approvedByUserId,
        });
      }

      // Zähler atomar anpassen
      firestoreBatch.update(batchRef, {
        'approvedTasks': FieldValue.increment(pendingCount),
        'pendingTasks': 0,
      });

      await firestoreBatch.commit();
      debugPrint('✅ Alle ausstehenden Aufgaben freigegeben in Batch: $batchId');
    } catch (e) {
      debugPrint('❌ Fehler beim Massen-Freigeben: $e');
      rethrow;
    }
  }

  /// Löscht einen kompletten Batch
  Future<void> deleteBatch({
    required String userId,
    required String batchId,
  }) async {
    try {
      final batchDoc = _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId);

      // Lösche alle Fragen
      final questionsSnapshot = await batchDoc.collection('questions').get();
      final batch = _firestore.batch();

      for (var doc in questionsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Lösche Hauptdokument
      batch.delete(batchDoc);

      await batch.commit();
      debugPrint('✅ Batch gelöscht: $batchId');
    } catch (e) {
      debugPrint('❌ Fehler beim Löschen: $e');
      rethrow;
    }
  }

  // ========================================================================
  // STATISTIKEN
  // ========================================================================

  /// Zählt die Anzahl der ausstehenden Aufgaben für einen User
  Future<int> getPendingTaskCount(String userId) async {
    try {
      final batchesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .get();

      int totalPending = 0;

      for (var batchDoc in batchesSnapshot.docs) {
        final pendingSnapshot = await batchDoc.reference
            .collection('questions')
            .where('status', isEqualTo: 'pending')
            .get();

        totalPending += pendingSnapshot.docs.length;
      }

      return totalPending;
    } catch (e) {
      debugPrint('❌ Fehler beim Zählen ausstehender Aufgaben: $e');
      return 0;
    }
  }

  /// Stream für Anzahl ausstehender Aufgaben
  Stream<int> watchPendingTaskCount(String userId) {
    return watchPendingBatches(userId).map((batches) {
      return batches.fold<int>(0, (acc, batch) => acc + batch.pendingTasks);
    });
  }

  // ========================================================================
  // ELTERN-AUFGABEN: FORTSCHRITTS-TRACKING
  // ========================================================================

  /// Markiert eine Eltern-Aufgabe als vom Kind korrekt beantwortet.
  /// [parentTaskRef] Format: "batchId/questionId"
  Future<void> markQuestionAnsweredCorrectly({
    required String userId,
    required String parentTaskRef,
  }) async {
    try {
      final parts = parentTaskRef.split('/');
      if (parts.length != 2) {
        debugPrint('⚠️ Ungültiger parentTaskRef: $parentTaskRef');
        return;
      }
      final batchId = parts[0];
      final questionId = parts[1];

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId)
          .collection('questions')
          .doc(questionId)
          .update({
            'answeredCorrectlyAt': FieldValue.serverTimestamp(),
            'answeredCorrectly': true,
          });

      debugPrint('✅ Eltern-Aufgabe als beantwortet markiert: $questionId');
    } catch (e) {
      debugPrint('❌ Fehler beim Markieren als beantwortet: $e');
    }
  }

  /// Lädt alle freigegebenen Eltern-Aufgaben, die das Kind noch NICHT
  /// korrekt beantwortet hat, für ein bestimmtes Fach.
  Future<List<GeneratedQuestion>> getUnansweredApprovedQuestions({
    required String userId,
    required String childId,
    required Subject subject,
  }) async {
    try {
      final batchesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .where('childId', isEqualTo: childId)
          .where('subject', isEqualTo: subject.value)
          .get();

      if (batchesSnapshot.docs.isEmpty) {
        debugPrint('ℹ️ Keine Batches für $childId / ${subject.value}');
        return [];
      }

      final unansweredQuestions = <GeneratedQuestion>[];

      for (var batchDoc in batchesSnapshot.docs) {
        // Alle approved Fragen laden (kein Filter auf answeredCorrectly in Firestore!)
        final questionsSnapshot = await batchDoc.reference
            .collection('questions')
            .where('status', isEqualTo: 'approved')
            .get();

        for (var qDoc in questionsSnapshot.docs) {
          final data = qDoc.data();
          // Clientseitig filtern: Feld fehlt (Altdaten) → noch nicht beantwortet
          // Feld ist false → noch nicht beantwortet
          // Feld ist true → bereits korrekt beantwortet, überspringen
          final answeredCorrectly = data['answeredCorrectly'] as bool? ?? false;
          if (!answeredCorrectly) {
            final question = GeneratedQuestion.fromFirestore(qDoc);
            // batchId für parentTaskRef mitgeben
            unansweredQuestions.add(question.copyWith(batchId: batchDoc.id));
          }
        }
      }

      debugPrint(
        '✅ ${unansweredQuestions.length} unbeantwortete Eltern-Aufgaben '
        'für ${subject.displayName} geladen',
      );
      return unansweredQuestions;
    } catch (e) {
      debugPrint('❌ Fehler beim Laden unbeantworteter Eltern-Aufgaben: $e');
      return [];
    }
  }
}

// ========================================================================
// RIVERPOD PROVIDERS
// ========================================================================

/// Provider für GeneratedTaskRepository
final generatedTaskRepositoryProvider = Provider<GeneratedTaskRepository>((
  ref,
) {
  return GeneratedTaskRepository();
});

/// Provider für alle Batches eines Users
final generatedBatchesProvider =
    StreamProvider.family<List<GeneratedTaskBatch>, String>((ref, userId) {
      final repository = ref.watch(generatedTaskRepositoryProvider);
      return repository.watchBatchesForUser(userId);
    });

/// Provider für ausstehende Batches
final pendingBatchesProvider =
    StreamProvider.family<List<GeneratedTaskBatch>, String>((ref, userId) {
      final repository = ref.watch(generatedTaskRepositoryProvider);
      return repository.watchPendingBatches(userId);
    });

/// Provider für Anzahl ausstehender Aufgaben (alle Kinder)
final pendingTaskCountProvider = StreamProvider.family<int, String>((
  ref,
  userId,
) {
  final repository = ref.watch(generatedTaskRepositoryProvider);
  return repository.watchPendingTaskCount(userId);
});

/// Provider für Batches gefiltert nach Kind
final generatedBatchesForChildProvider =
    StreamProvider.family<
      List<GeneratedTaskBatch>,
      ({String userId, String childId})
    >((ref, params) {
      final repository = ref.watch(generatedTaskRepositoryProvider);
      return repository.watchBatchesForChild(params.userId, params.childId);
    });

/// Provider für Anzahl ausstehender Aufgaben eines bestimmten Kindes
final pendingTaskCountForChildProvider =
    StreamProvider.family<int, ({String userId, String childId})>((
      ref,
      params,
    ) {
      final repository = ref.watch(generatedTaskRepositoryProvider);
      return repository.watchPendingTaskCountForChild(
        params.userId,
        params.childId,
      );
    });

/// Provider für Live-Fragen eines einzelnen Batches
final batchQuestionsProvider =
    StreamProvider.family<
      List<GeneratedQuestion>,
      ({String userId, String batchId})
    >((ref, params) {
      final repository = ref.watch(generatedTaskRepositoryProvider);
      return repository.watchQuestionsForBatch(params.userId, params.batchId);
    });

/// Provider für freigegebene Aufgaben eines Kindes in einem Fach
final approvedQuestionsProvider =
    FutureProvider.family<List<GeneratedQuestion>, ApprovedQuestionsParams>((
      ref,
      params,
    ) async {
      final repository = ref.watch(generatedTaskRepositoryProvider);
      return repository.getApprovedQuestionsForChild(
        userId: params.userId,
        childId: params.childId,
        subject: params.subject,
      );
    });
