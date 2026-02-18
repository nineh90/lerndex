import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🗑️ TUTOR CHAT CLEANUP SERVICE
///
/// Zuständigkeiten:
/// 1. Löscht manuell eine einzelne Session (inkl. Sub-Collection messages)
/// 2. Löscht automatisch alle Sessions älter als 14 Tage
///    → wird beim App-Start ausgeführt, max. einmal pro Tag
///
/// Löscht immer vollständig:
///   users/{uid}/children/{childId}/tutor_sessions/{sessionId}/messages/*
///   users/{uid}/children/{childId}/tutor_sessions/{sessionId}
///   users/{uid}/children/{childId}/active_tutor_chat/*  (falls Session aktiv)

class TutorChatCleanupService {
  final FirebaseFirestore _firestore;

  TutorChatCleanupService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────────────────────────
  // MANUELLES LÖSCHEN
  // ──────────────────────────────────────────────────────────────────────────

  /// Löscht eine einzelne Session inkl. aller Nachrichten.
  /// Markiert die Session zusätzlich als 'deleted' BEVOR sie gelöscht wird,
  /// damit das Schülerdashboard sie sofort ausfiltert – auch bei Offline-Cache.
  Future<void> deleteSession({
    required String userId,
    required String childId,
    required String sessionId,
  }) async {
    print('🗑️ Lösche Session $sessionId...');

    // 1. Session sofort als 'deleted' markieren → Schülerdashboard filtert sie
    //    sofort aus, auch wenn der Delete noch läuft oder gecacht ist
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .update({'status': 'deleted'});

    // 2. Alle messages der Session löschen (Batch)
    await _deleteSubCollection(
      path: 'users/$userId/children/$childId/tutor_sessions/$sessionId/messages',
    );

    // 3. Session-Dokument selbst löschen
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .delete();

    // 4. active_tutor_chat leeren (falls diese Session die aktive war)
    await _clearActiveTutorChat(userId: userId, childId: childId);

    print('✅ Session $sessionId gelöscht');
  }

  /// Löscht alle Sessions eines Kindes.
  Future<void> deleteAllSessionsForChild({
    required String userId,
    required String childId,
  }) async {
    print('🗑️ Lösche alle Sessions für Kind $childId...');

    final sessionsSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .get();

    for (final doc in sessionsSnapshot.docs) {
      await deleteSession(
        userId: userId,
        childId: childId,
        sessionId: doc.id,
      );
    }

    print('✅ Alle Sessions für Kind $childId gelöscht');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AUTOMATISCHER 14-TAGE-CLEANUP
  // ──────────────────────────────────────────────────────────────────────────

  static const int _retentionDays = 14;
  static const String _lastCleanupKey = 'tutor_last_cleanup';

  /// Führt Cleanup aus – aber maximal einmal alle 24 Stunden.
  /// Wird beim App-Start aufgerufen.
  Future<void> runAutoCleanupIfNeeded({required String userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCleanupMs = prefs.getInt(_lastCleanupKey) ?? 0;
    final lastCleanup = DateTime.fromMillisecondsSinceEpoch(lastCleanupMs);
    final now = DateTime.now();

    // Nur einmal pro Tag ausführen
    if (now.difference(lastCleanup).inHours < 24) {
      print('⏭️ Chat-Cleanup: Heute schon gelaufen, überspringe');
      return;
    }

    print('🧹 Starte automatischen 14-Tage Chat-Cleanup...');
    await runAutoCleanup(userId: userId);

    // Zeitstempel speichern
    await prefs.setInt(_lastCleanupKey, now.millisecondsSinceEpoch);
    print('✅ Auto-Cleanup abgeschlossen, nächster in 24h');
  }

  /// Löscht alle abgeschlossenen Sessions aller Kinder, die älter als 14 Tage sind.
  Future<void> runAutoCleanup({required String userId}) async {
    final cutoff = DateTime.now().subtract(const Duration(days: _retentionDays));
    final cutoffTimestamp = Timestamp.fromDate(cutoff);

    print('🧹 Lösche Sessions älter als ${cutoff.day}.${cutoff.month}.${cutoff.year}...');

    // Alle Kinder des Users
    final childrenSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .get();

    int totalDeleted = 0;

    for (final childDoc in childrenSnapshot.docs) {
      final childId = childDoc.id;

      // Nur abgeschlossene Sessions löschen, nicht aktive
      final oldSessionsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('tutor_sessions')
          .where('status', isEqualTo: 'completed')
          .where('startedAt', isLessThan: cutoffTimestamp)
          .get();

      if (oldSessionsSnapshot.docs.isEmpty) {
        print('   Kind $childId: Keine alten Sessions');
        continue;
      }

      print('   Kind $childId: ${oldSessionsSnapshot.docs.length} alte Sessions werden gelöscht');

      for (final sessionDoc in oldSessionsSnapshot.docs) {
        await deleteSession(
          userId: userId,
          childId: childId,
          sessionId: sessionDoc.id,
        );
        totalDeleted++;
      }
    }

    print('✅ Auto-Cleanup: $totalDeleted Sessions gelöscht');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HILFSMETHODEN
  // ──────────────────────────────────────────────────────────────────────────

  /// Löscht eine Firestore Sub-Collection in Batches (max 500 pro Batch).
  Future<void> _deleteSubCollection({required String path}) async {
    const batchSize = 400;

    while (true) {
      final snapshot = await _firestore
          .collection(path)
          .limit(batchSize)
          .get();

      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) break;
    }
  }

  /// Leert die active_tutor_chat Collection eines Kindes.
  Future<void> _clearActiveTutorChat({
    required String userId,
    required String childId,
  }) async {
    await _deleteSubCollection(
      path: 'users/$userId/children/$childId/active_tutor_chat',
    );
  }
}

/// Singleton-artige Instanz für einfachen Zugriff
final tutorChatCleanupService = TutorChatCleanupService();