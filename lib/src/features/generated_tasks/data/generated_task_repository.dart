import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'generated_task_models.dart';

/// 🗄️ REPOSITORY FÜR GENERIERTE AUFGABEN
/// Verwaltet das Speichern, Laden und Freigeben von KI-generierten Aufgaben
class GeneratedTaskRepository {
  GeneratedTaskRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storageOverride = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storageOverride;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  /// Batches, deren freigegebene Aufgaben das Kind schon alle gelöst hat –
  /// mit der Zahl freigegebener Aufgaben zu dem Zeitpunkt. Solange die gleich
  /// bleibt, muss der Quizstart dort nicht noch einmal nachsehen.
  final Map<String, int> _doneBatches = {};

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

  /// Lehrkraft: dieselben (schon geprüften) Aufgaben an mehrere Schüler
  /// geben. Pro Kind entsteht ein eigener, bereits freigegebener Batch – so
  /// läuft auf der Kinderseite alles wie bei Eltern-Aufgaben. Die Batches
  /// eines Auftrags teilen sich die assignmentId (Übersicht für die Klasse).
  Future<String> assignToStudents({
    required String ownerUid,
    required String classId,
    required List<({String id, String name})> students,
    required Subject subject,
    required String title,
    required List<GeneratedQuestion> questions,
    required String assignedBy,
    String imageUrl = '',
  }) async {
    final assignmentId = _firestore.collection('_').doc().id;
    final batches = _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('generated_batches');
    // Firestore schreibt höchstens 500 Dokumente pro Batch-Write
    var writes = _firestore.batch();
    var count = 0;
    Future<void> add(DocumentReference ref, Map<String, dynamic> data) async {
      writes.set(ref, data);
      if (++count >= 450) {
        await writes.commit();
        writes = _firestore.batch();
        count = 0;
      }
    }

    for (final student in students) {
      final batchDoc = batches.doc();
      await add(batchDoc, {
        'childId': student.id,
        'childName': student.name,
        'subject': subject.value,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'totalTasks': questions.length,
        'pendingTasks': 0,
        'approvedTasks': questions.length,
        'rejectedTasks': 0,
        'classId': classId,
        'assignmentId': assignmentId,
        'title': title,
        'assignedBy': assignedBy,
      });
      for (final q in questions) {
        await add(batchDoc.collection('questions').doc(), {
          ...q.toFirestore(),
          'status': TaskApprovalStatus.approved.value,
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': assignedBy,
        });
      }
    }
    if (count > 0) await writes.commit();
    return assignmentId;
  }

  /// Lehrkraft: Aufträge einer Klasse (ein Eintrag pro assignmentId).
  Stream<List<ClassAssignment>> watchClassAssignments(
    String ownerUid,
    String classId,
  ) {
    return _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('generated_batches')
        .where('classId', isEqualTo: classId)
        .snapshots()
        .map((snap) {
          final byId = <String, ClassAssignment>{};
          for (final doc in snap.docs) {
            final d = doc.data();
            final id = d['assignmentId'] as String? ?? doc.id;
            final existing = byId[id];
            byId[id] = ClassAssignment(
              id: id,
              title: d['title'] as String? ?? '',
              subject: SubjectExtension.fromString(
                d['subject'] as String? ?? 'mathe',
              ),
              createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
              tasks: d['totalTasks'] as int? ?? 0,
              students: (existing?.students ?? 0) + 1,
            );
          }
          final list = byId.values.toList()
            ..sort(
              (a, b) => (b.createdAt ?? DateTime(2100)).compareTo(
                a.createdAt ?? DateTime(2100),
              ),
            );
          return list;
        });
  }

  /// Lehrkraft: Auftrag zurückziehen (alle Batches samt Aufgaben und Foto).
  ///
  /// Das Foto löschen dürfen Lehrkräfte laut storage.rules nicht – der
  /// Fehler wird geschluckt, den Rest räumt der Server auf.
  Future<void> deleteAssignment(String ownerUid, String assignmentId) async {
    final batches = await _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('generated_batches')
        .where('assignmentId', isEqualTo: assignmentId)
        .get();
    final imageUrls = <String>{};
    for (final batchDoc in batches.docs) {
      final imageUrl = batchDoc.data()['imageUrl'] as String?;
      if (imageUrl != null && imageUrl.isNotEmpty) imageUrls.add(imageUrl);
      final questions = await batchDoc.reference.collection('questions').get();
      final writes = _firestore.batch();
      for (final q in questions.docs) {
        writes.delete(q.reference);
      }
      writes.delete(batchDoc.reference);
      await writes.commit();
    }
    for (final url in imageUrls) {
      await deleteTaskImage(url);
    }
  }

  /// Löscht ein Aufgaben-Foto aus Storage (best effort: Lehrkräfte dürfen
  /// das nicht, das Foto kann schon weg sein).
  Future<void> deleteTaskImage(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    try {
      await _storage.refFromURL(imageUrl).delete();
    } catch (e) {
      debugPrint('⚠️ Aufgaben-Foto nicht gelöscht: $e');
    }
  }

  // ========================================================================
  // AUFGABEN LADEN
  // ========================================================================

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

      // Zugehöriges Aufgaben-Foto in Storage mitlöschen (DSGVO):
      // sonst bleibt das Bild nach dem Löschen des Batches verwaist liegen.
      try {
        final snapshot = await batchDoc.get();
        await deleteTaskImage(snapshot.data()?['imageUrl'] as String? ?? '');
      } catch (e) {
        debugPrint('⚠️ Batch-Foto konnte nicht gelöscht werden: $e');
      }

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
  ///
  /// Weniger Abfragen pro Quizstart: Batches ohne freigegebene Aufgaben
  /// (Zähler approvedTasks = 0) und Batches, die das Kind in dieser
  /// App-Sitzung schon komplett gelöst hat, werden übersprungen.
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
        final approvedTasks = batchDoc.data()['approvedTasks'] as int?;
        if (approvedTasks == 0) continue;
        if (approvedTasks != null &&
            _doneBatches[batchDoc.id] == approvedTasks) {
          continue;
        }

        // Alle approved Fragen laden (kein Filter auf answeredCorrectly in Firestore!)
        final questionsSnapshot = await batchDoc.reference
            .collection('questions')
            .where('status', isEqualTo: 'approved')
            .get();

        final before = unansweredQuestions.length;
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
        if (approvedTasks != null &&
            unansweredQuestions.length == before &&
            questionsSnapshot.docs.length == approvedTasks) {
          _doneBatches[batchDoc.id] = approvedTasks;
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

/// Ein Klassenauftrag der Lehrkraft (dieselben Aufgaben für mehrere Kinder).
class ClassAssignment {
  const ClassAssignment({
    required this.id,
    required this.title,
    required this.subject,
    required this.createdAt,
    required this.tasks,
    required this.students,
  });

  final String id;
  final String title;
  final Subject subject;
  final DateTime? createdAt;
  final int tasks;
  final int students;
}
