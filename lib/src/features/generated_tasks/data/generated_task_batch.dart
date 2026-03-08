import 'package:cloud_firestore/cloud_firestore.dart';
import 'generated_task_models.dart';

/// 📦 BATCH VON GENERIERTEN AUFGABEN
/// Ein Batch repräsentiert alle Aufgaben, die aus einem hochgeladenen Foto generiert wurden
class GeneratedTaskBatch {
  final String id;
  final String childId;
  final String childName;
  final Subject subject;
  final String imageUrl;
  final DateTime createdAt;
  final int totalTasks;
  final int approvedTasks;
  final int pendingTasks;
  final int rejectedTasks;
  final List<GeneratedQuestion> questions;

  GeneratedTaskBatch({
    required this.id,
    required this.childId,
    required this.childName,
    required this.subject,
    required this.imageUrl,
    required this.createdAt,
    required this.totalTasks,
    required this.approvedTasks,
    required this.pendingTasks,
    required this.rejectedTasks,
    required this.questions,
  });

  factory GeneratedTaskBatch.fromFirestore(
    DocumentSnapshot doc,
    List<GeneratedQuestion> questions,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    // Zähler direkt aus dem Dokument lesen (werden bei approve/reject atomar gepflegt).
    // Für alte Batches ohne diese Felder: totalTasks als pendingTasks annehmen —
    // die Migration in watchBatchesForChild schreibt die echten Werte beim nächsten Öffnen.
    final hasStoredCounters =
        data.containsKey('pendingTasks') &&
        data.containsKey('approvedTasks') &&
        data.containsKey('rejectedTasks');

    final int approved;
    final int pending;
    final int rejected;
    final int total = (data['totalTasks'] as num?)?.toInt() ?? 0;

    if (hasStoredCounters) {
      approved = (data['approvedTasks'] as num?)?.toInt() ?? 0;
      pending = (data['pendingTasks'] as num?)?.toInt() ?? 0;
      rejected = (data['rejectedTasks'] as num?)?.toInt() ?? 0;
    } else {
      // Alter Batch: Felder noch nicht vorhanden → als komplett ausstehend behandeln
      approved = 0;
      pending = total;
      rejected = 0;
    }

    return GeneratedTaskBatch(
      id: doc.id,
      childId: data['childId'] ?? '',
      childName: data['childName'] ?? '',
      subject: SubjectExtension.fromString(data['subject'] ?? 'mathe'),
      imageUrl: data['imageUrl'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalTasks: (data['totalTasks'] as num?)?.toInt() ?? questions.length,
      approvedTasks: approved,
      pendingTasks: pending,
      rejectedTasks: rejected,
      questions: questions,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'childName': childName,
      'subject': subject.value,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'totalTasks': totalTasks,
    };
  }

  /// Gibt true zurück, wenn alle Aufgaben bearbeitet wurden (approved oder rejected)
  bool get isFullyReviewed => pendingTasks == 0;

  /// Gibt true zurück, wenn mindestens eine Aufgabe freigegeben wurde
  bool get hasApprovedTasks => approvedTasks > 0;

  /// Fortschritt der Freigabe in Prozent (0-100)
  double get reviewProgress {
    if (totalTasks == 0) return 0;
    return ((approvedTasks + rejectedTasks) / totalTasks * 100);
  }
}
