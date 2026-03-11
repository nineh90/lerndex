import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tutor_session_model.dart';
import '../domain/chat_message.dart';
import '../../auth/data/auth_repository.dart';

/// 🗄️ TUTOR SESSION REPOSITORY
/// Verwaltet Session-Speicherung in Firestore
class TutorSessionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ========================================================================
  // SESSION MANAGEMENT
  // ========================================================================

  /// Erstellt eine neue Session
  Future<TutorSession> createSession({
    required String userId,
    required String childId,
  }) async {
    debugPrint('📝 Erstelle neue Tutor-Session für Kind: $childId');

    final sessionData = TutorSession(
      id: '', // Wird von Firestore gesetzt
      childId: childId,
      startedAt: DateTime.now(),
      status: 'active',
    );

    final docRef = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .add(sessionData.toMap());

    debugPrint('✅ Session erstellt: ${docRef.id}');

    return sessionData.copyWith(id: docRef.id);
  }

  /// Holt aktive Session oder erstellt neue
  Future<TutorSession> getOrCreateActiveSession({
    required String userId,
    required String childId,
  }) async {
    debugPrint('🔍 Suche aktive Session für Kind: $childId');

    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .where('status', isEqualTo: 'active')
        .orderBy('startedAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final session = TutorSession.fromFirestore(doc.data(), doc.id);

      final now = DateTime.now();
      final timeSinceStart = now.difference(session.startedAt);

      if (timeSinceStart.inMinutes > 30) {
        debugPrint(
          '⏰ Session zu alt (${timeSinceStart.inMinutes} Min), schließe ab',
        );
        await completeSession(
          userId: userId,
          childId: childId,
          sessionId: session.id,
        );
        return createSession(userId: userId, childId: childId);
      }

      debugPrint('✅ Aktive Session gefunden: ${session.id}');
      return session;
    }

    debugPrint('📝 Keine aktive Session, erstelle neue');
    return createSession(userId: userId, childId: childId);
  }

  /// Aktualisiert Session-Metadaten
  Future<void> updateSession({
    required String userId,
    required String childId,
    required String sessionId,
    int? messageCount,
    String? detectedTopic,
    String? firstQuestion,
    String? contentFlag,
  }) async {
    final updates = <String, dynamic>{};

    if (messageCount != null) updates['messageCount'] = messageCount;
    if (detectedTopic != null) updates['detectedTopic'] = detectedTopic;
    if (firstQuestion != null) updates['firstQuestion'] = firstQuestion;
    if (contentFlag != null) updates['contentFlag'] = contentFlag;

    if (updates.isEmpty) return;

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .update(updates);
  }

  /// Schließt eine Session ab
  Future<void> completeSession({
    required String userId,
    required String childId,
    required String sessionId,
  }) async {
    debugPrint('🏁 Schließe Session ab: $sessionId');

    final now = DateTime.now();

    final sessionDoc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .get();

    if (!sessionDoc.exists) return;

    final session = TutorSession.fromFirestore(
      sessionDoc.data()!,
      sessionDoc.id,
    );

    final duration = now.difference(session.startedAt);

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .update({
          'status': 'completed',
          'endedAt': Timestamp.fromDate(now),
          'durationSeconds': duration.inSeconds,
        });

    debugPrint('✅ Session abgeschlossen. Dauer: ${duration.inMinutes} Min');
  }

  // ========================================================================
  // MESSAGE MANAGEMENT
  // ========================================================================

  /// Speichert Nachricht in Session UND in active_tutor_chat
  Future<void> saveMessage({
    required String userId,
    required String childId,
    required String sessionId,
    required ChatMessage message,
  }) async {
    final messageData = {
      'text': message.text,
      'isUser': message.isUser,
      'timestamp': Timestamp.fromDate(message.timestamp),
    };

    // 1. In Session speichern (permanent für Eltern)
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .collection('messages')
        .doc(message.id)
        .set(messageData);

    // 2. In active_tutor_chat speichern (temporär für Schüler)
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('active_tutor_chat')
        .doc(message.id)
        .set(messageData);

    // 3. Session-Counter erhöhen
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .update({'messageCount': FieldValue.increment(1)});

    // 4. Jede User-Nachricht auf Thema + Content-Flag prüfen
    if (message.isUser) {
      await _analyzeUserMessage(
        userId: userId,
        childId: childId,
        sessionId: sessionId,
        messageText: message.text,
      );
    }
  }

  // ========================================================================
  // CONTENT ANALYSE
  // ========================================================================

  /// Analysiert eine User-Nachricht und aktualisiert Thema + Content-Flag.
  ///
  /// Regeln:
  /// - Thema + firstQuestion werden nur beim ERSTEN Mal gesetzt
  /// - contentFlag wird bei JEDER Nachricht geprüft
  /// - 'critical' überschreibt 'off_topic', aber nie umgekehrt
  ///   → einmal critical = immer critical für diese Session
  Future<void> _analyzeUserMessage({
    required String userId,
    required String childId,
    required String sessionId,
    required String messageText,
  }) async {
    // Aktuelle Session laden um bestehenden Flag + firstQuestion zu kennen
    final sessionDoc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .get();

    final session = TutorSession.fromFirestore(
      sessionDoc.data()!,
      sessionDoc.id,
    );

    final updates = <String, dynamic>{};

    // Thema + firstQuestion nur beim ersten Mal setzen
    if (session.firstQuestion == null) {
      final topic = TutorSession.detectTopic(messageText);
      updates['firstQuestion'] = messageText;
      updates['detectedTopic'] = topic;
      debugPrint('🎯 Thema erkannt: $topic');
    }

    // Content-Flag bei JEDER Nachricht neu prüfen –
    // aber 'critical' nie durch ein schwächeres Flag überschreiben
    final alreadyCritical = session.contentFlag == 'critical';

    if (!alreadyCritical) {
      final newFlag = TutorSession.detectContentFlag(messageText);

      if (newFlag != null && newFlag != session.contentFlag) {
        updates['contentFlag'] = newFlag;
        debugPrint('🚩 Content-Flag gesetzt: $newFlag');
      }
    }

    if (updates.isNotEmpty) {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('tutor_sessions')
          .doc(sessionId)
          .update(updates);
    }
  }

  // ========================================================================
  // SCHÜLER-CHAT MANAGEMENT
  // ========================================================================

  /// Löscht active_tutor_chat (Schüler-Ansicht)
  Future<void> clearActiveChatForStudent({
    required String userId,
    required String childId,
  }) async {
    debugPrint('🗑️ Lösche active_tutor_chat für Schüler');

    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('active_tutor_chat')
        .get();

    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    debugPrint('✅ Active Chat gelöscht (${snapshot.docs.length} Nachrichten)');
  }

  /// Lädt Nachrichten aus active_tutor_chat (für Schüler)
  Future<List<ChatMessage>> loadActiveChatMessages({
    required String userId,
    required String childId,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('active_tutor_chat')
        .orderBy('timestamp', descending: false)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return ChatMessage(
        id: doc.id,
        text: data['text'] ?? '',
        isUser: data['isUser'] ?? false,
        timestamp: (data['timestamp'] as Timestamp).toDate(),
      );
    }).toList();
  }

  /// Lädt Nachrichten einer Session (für Eltern)
  Future<List<ChatMessage>> loadSessionMessages({
    required String userId,
    required String childId,
    required String sessionId,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return ChatMessage(
        id: doc.id,
        text: data['text'] ?? '',
        isUser: data['isUser'] ?? false,
        timestamp: (data['timestamp'] as Timestamp).toDate(),
      );
    }).toList();
  }

  // ========================================================================
  // QUERIES FÜR ELTERN
  // ========================================================================

  /// Stream aller Sessions für ein Kind
  Stream<List<TutorSession>> watchSessions({
    required String userId,
    required String childId,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return TutorSession.fromFirestore(doc.data(), doc.id);
          }).toList();
        });
  }

  /// Holt einzelne Session
  Future<TutorSession?> getSession({
    required String userId,
    required String childId,
    required String sessionId,
  }) async {
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('tutor_sessions')
        .doc(sessionId)
        .get();

    if (!doc.exists) return null;

    return TutorSession.fromFirestore(doc.data()!, doc.id);
  }
}

// ========================================================================
// RIVERPOD PROVIDER
// ========================================================================

final tutorSessionRepositoryProvider = Provider<TutorSessionRepository>((ref) {
  return TutorSessionRepository();
});

/// Provider für aktive Session eines Kindes
final activeSessionProvider = FutureProvider.family<TutorSession?, String>((
  ref,
  childId,
) async {
  final repository = ref.watch(tutorSessionRepositoryProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  final userId = authRepo.currentUser?.uid;

  if (userId == null) return null;

  try {
    return await repository.getOrCreateActiveSession(
      userId: userId,
      childId: childId,
    );
  } catch (e) {
    debugPrint('❌ Fehler beim Laden der aktiven Session: $e');
    return null;
  }
});
