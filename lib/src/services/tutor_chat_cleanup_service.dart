import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// 🗑️ TUTOR CHAT CLEANUP SERVICE
///
/// Löscht Lexi-Gespräche, die Eltern im Verlauf entfernen:
///   users/{uid}/children/{childId}/tutor_sessions/{sessionId}/messages/*
///   users/{uid}/children/{childId}/tutor_sessions/{sessionId}
///   users/{uid}/children/{childId}/active_tutor_chat/*  (nur wenn die
///   gelöschte Session die aktive war)
///
/// Gespräche und Arbeitsblatt-Fotos älter als 14 Tage löscht eine geplante
/// Cloud Function für alle Konten (auch Schulen) – das macht die App nicht
/// mehr selbst.
///
/// Verbundene Eltern eines Schulkinds (`users/school_<id>/…`) dürfen laut
/// firestore.rules nur lesen und löschen, nicht ändern – deshalb wird hier
/// nichts vorher aktualisiert. Fotos von Schulkindern löschen sie nicht
/// (storage.rules), die räumt der Server ab.
class TutorChatCleanupService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storageOverride;

  TutorChatCleanupService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storageOverride = storage;

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  /// Löscht eine einzelne Session inkl. aller Nachrichten. Fehler (z.B.
  /// fehlende Rechte) werden weitergegeben, damit die Oberfläche sie zeigt.
  Future<void> deleteSession({
    required String userId,
    required String childId,
    required String sessionId,
  }) async {
    final sessionRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId);

    final snapshot = await sessionRef.get();
    final wasActive = snapshot.data()?['status'] == 'active';

    // 1. Alle Nachrichten der Session löschen (Batch)
    await _deleteSubCollection(
      path:
          'users/$userId/children/$childId/tutor_sessions/$sessionId/messages',
      deleteImages: !_isSchoolAccount(userId),
    );

    // 2. Session-Dokument selbst löschen
    await sessionRef.delete();

    // 3. active_tutor_chat leeren – nur wenn diese Session die aktive war
    if (wasActive) {
      try {
        await _deleteSubCollection(
          path: 'users/$userId/children/$childId/active_tutor_chat',
          deleteImages: false,
        );
      } catch (e) {
        debugPrint('⚠️ active_tutor_chat nicht geleert: $e');
      }
    }
  }

  /// Löscht alle Sessions eines Kindes.
  Future<void> deleteAllSessionsForChild({
    required String userId,
    required String childId,
  }) async {
    final sessionsSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .get();

    for (final doc in sessionsSnapshot.docs) {
      await deleteSession(userId: userId, childId: childId, sessionId: doc.id);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HILFSMETHODEN
  // ──────────────────────────────────────────────────────────────────────────

  static bool _isSchoolAccount(String userId) => userId.startsWith('school_');

  /// Löscht eine Firestore Sub-Collection in Batches (max. 400 pro Batch).
  /// Mit [deleteImages] wird das Foto einer Nachricht (imageUrl) in Storage
  /// mitgelöscht, sonst bliebe das Aufgabenblatt verwaist liegen (DSGVO).
  Future<void> _deleteSubCollection({
    required String path,
    required bool deleteImages,
  }) async {
    const batchSize = 400;

    while (true) {
      final snapshot = await _firestore.collection(path).limit(batchSize).get();

      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        if (deleteImages) await _deleteAttachedImage(doc.data());
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) break;
    }
  }

  /// Löscht das in einer Message referenzierte Storage-Bild (best effort).
  Future<void> _deleteAttachedImage(Map<String, dynamic> data) async {
    final imageUrl = data['imageUrl'];
    if (imageUrl is! String || imageUrl.isEmpty) return;
    try {
      await _storage.refFromURL(imageUrl).delete();
    } catch (e) {
      // Bild existiert nicht mehr o.ä. – Löschen nicht blockieren
      debugPrint('⚠️ Chat-Bild konnte nicht gelöscht werden: $e');
    }
  }
}

/// Singleton-artige Instanz für einfachen Zugriff
final tutorChatCleanupService = TutorChatCleanupService();
