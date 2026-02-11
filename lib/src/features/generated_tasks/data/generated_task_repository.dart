import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'generated_task_models.dart';

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

      // Hauptdokument
      batch.set(batchDoc, {
        'childId': childId,
        'childName': childName,
        'subject': subject.value,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'totalTasks': questions.length,
      });

      // Einzelne Fragen als Sub-Collection
      for (var question in questions) {
        final questionDoc = batchDoc.collection('questions').doc();
        batch.set(questionDoc, question.toFirestore());
      }

      await batch.commit();
      print('✅ Batch gespeichert: ${batchDoc.id} mit ${questions.length} Aufgaben');

      return batchDoc.id;
    } catch (e) {
      print('❌ Fehler beim Speichern des Batches: $e');
      rethrow;
    }
  }

  // ========================================================================
  // AUFGABEN LADEN
  // ========================================================================

  /// Lädt alle Batches für einen User (für Eltern-Dashboard)
  Stream<List<GeneratedTaskBatch>> watchBatchesForUser(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('generated_batches')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final batches = <GeneratedTaskBatch>[];

      for (var doc in snapshot.docs) {
        // Lade alle Fragen für diesen Batch
        final questionsSnapshot = await doc.reference.collection('questions').get();
        final questions = questionsSnapshot.docs
            .map((qDoc) => GeneratedQuestion.fromFirestore(qDoc))
            .toList();

        batches.add(GeneratedTaskBatch.fromFirestore(doc, questions));
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

      final questionsSnapshot = await doc.reference.collection('questions').get();
      final questions = questionsSnapshot.docs
          .map((qDoc) => GeneratedQuestion.fromFirestore(qDoc))
          .toList();

      return GeneratedTaskBatch.fromFirestore(doc, questions);
    } catch (e) {
      print('❌ Fehler beim Laden des Batches: $e');
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

      print('✅ ${approvedQuestions.length} freigegebene Aufgaben geladen für ${subject.displayName}');
      return approvedQuestions;
    } catch (e) {
      print('❌ Fehler beim Laden freigegebener Aufgaben: $e');
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
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId)
          .collection('questions')
          .doc(questionId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': approvedByUserId,
      });

      print('✅ Aufgabe freigegeben: $questionId');
    } catch (e) {
      print('❌ Fehler beim Freigeben: $e');
      rethrow;
    }
  }

  /// Lehnt eine Aufgabe ab (reject)
  Future<void> rejectQuestion({
    required String userId,
    required String batchId,
    required String questionId,
    String? reason,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId)
          .collection('questions')
          .doc(questionId)
          .update({
        'status': 'rejected',
        'rejectionReason': reason,
        'approvedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Aufgabe abgelehnt: $questionId');
    } catch (e) {
      print('❌ Fehler beim Ablehnen: $e');
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
      final questionsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('generated_batches')
          .doc(batchId)
          .collection('questions')
          .where('status', isEqualTo: 'pending')
          .get();

      final batch = _firestore.batch();

      for (var doc in questionsSnapshot.docs) {
        batch.update(doc.reference, {
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': approvedByUserId,
        });
      }

      await batch.commit();
      print('✅ Alle ausstehenden Aufgaben freigegeben in Batch: $batchId');
    } catch (e) {
      print('❌ Fehler beim Massen-Freigeben: $e');
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
      print('✅ Batch gelöscht: $batchId');
    } catch (e) {
      print('❌ Fehler beim Löschen: $e');
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
      print('❌ Fehler beim Zählen ausstehender Aufgaben: $e');
      return 0;
    }
  }

  /// Stream für Anzahl ausstehender Aufgaben
  Stream<int> watchPendingTaskCount(String userId) {
    return watchPendingBatches(userId).map((batches) {
      return batches.fold<int>(0, (sum, batch) => sum + batch.pendingTasks);
    });
  }
}

// ========================================================================
// RIVERPOD PROVIDERS
// ========================================================================

/// Provider für GeneratedTaskRepository
final generatedTaskRepositoryProvider = Provider<GeneratedTaskRepository>((ref) {
  return GeneratedTaskRepository();
});

/// Provider für alle Batches eines Users
final generatedBatchesProvider = StreamProvider.family<List<GeneratedTaskBatch>, String>(
      (ref, userId) {
    final repository = ref.watch(generatedTaskRepositoryProvider);
    return repository.watchBatchesForUser(userId);
  },
);

/// Provider für ausstehende Batches
final pendingBatchesProvider = StreamProvider.family<List<GeneratedTaskBatch>, String>(
      (ref, userId) {
    final repository = ref.watch(generatedTaskRepositoryProvider);
    return repository.watchPendingBatches(userId);
  },
);

/// Provider für Anzahl ausstehender Aufgaben
final pendingTaskCountProvider = StreamProvider.family<int, String>(
      (ref, userId) {
    final repository = ref.watch(generatedTaskRepositoryProvider);
    return repository.watchPendingTaskCount(userId);
  },
);

/// Provider für freigegebene Aufgaben eines Kindes in einem Fach
final approvedQuestionsProvider = FutureProvider.family<List<GeneratedQuestion>, ApprovedQuestionsParams>(
      (ref, params) async {
    final repository = ref.watch(generatedTaskRepositoryProvider);
    return repository.getApprovedQuestionsForChild(
      userId: params.userId,
      childId: params.childId,
      subject: params.subject,
    );
  },
);

/// Parameter für approvedQuestionsProvider
class ApprovedQuestionsParams {
  final String userId;
  final String childId;
  final Subject subject;

  ApprovedQuestionsParams({
    required this.userId,
    required this.childId,
    required this.subject,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ApprovedQuestionsParams &&
              runtimeType == other.runtimeType &&
              userId == other.userId &&
              childId == other.childId &&
              subject == other.subject;

  @override
  int get hashCode => userId.hashCode ^ childId.hashCode ^ subject.hashCode;
}