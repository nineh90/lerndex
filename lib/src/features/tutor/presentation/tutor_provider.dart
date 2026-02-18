import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/chat_message.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../../ai/firebase_ai_service.dart';

/// 💬 TUTOR PROVIDER - PRO KIND (OPTIMIERT)
/// - Sofortige Begrüßung (kein Loading!)
/// - Chat-Historie wird im Hintergrund geladen
/// - Jedes Kind hat eigenen Chat
/// - NEU: Speichert auch in tutor_sessions für Eltern
/// - FIX: Session-basiertes Löschen (tutor_chat bleibt pro Session erhalten)
/// - FIX: Timestamp nutzt lokale Zeit statt serverTimestamp (verhindert UTC-Bug)

class TutorNotifier extends StateNotifier<List<ChatMessage>> {
  TutorNotifier(
      this._aiService,
      this._ref,
      this._childId,
      this._userId,
      ) : super([]) {
    _initializeWithWelcome();
  }

  final FirebaseAIService _aiService;
  final Ref _ref;
  final String _childId;
  final String _userId;
  bool _isAIInitialized = false;
  bool _isLoadingHistory = false;
  String? _currentSessionId; // NEU: Für Session-Tracking

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// SOFORTIGE Initialisierung mit Begrüßung
  void _initializeWithWelcome() {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    // ✅ SOFORT Begrüßung anzeigen (ohne Wartezeit!)
    final welcomeMessage = ChatMessage.tutor(
      'Hallo ${child.name}! 👋 Ich bin **Lerndex**, dein persönlicher Lernbegleiter! 🎓 Ich helfe dir bei allen Fragen zu Mathe, Deutsch, Englisch und anderen Schulfächern. Was möchtest du heute lernen? 📚✨',
    );

    state = [welcomeMessage];

    // Im Hintergrund: Alte Historie laden (falls vorhanden)
    _loadChatHistoryInBackground();
  }

  /// Lädt Chat-Historie im Hintergrund (ohne UI zu blockieren)
  /// FIX: Lädt aus der aktiven Session statt aus tutor_chat
  Future<void> _loadChatHistoryInBackground() async {
    if (_isLoadingHistory) return;
    _isLoadingHistory = true;

    try {
      print('📚 Lade Chat-Historie für Kind $_childId im Hintergrund...');

      // Prüfe ob aktive Session existiert
      final sessionSnapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (sessionSnapshot.docs.isEmpty) {
        print('   → Keine aktive Session, speichere Begrüßung in neuer Session');
        await _saveChatMessage(state.first);
        return;
      }

      // Aktive Session gefunden – Nachrichten laden
      _currentSessionId = sessionSnapshot.docs.first.id;
      print('   → Aktive Session gefunden: $_currentSessionId');

      final messagesSnapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(_currentSessionId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .limit(50)
          .get();

      if (messagesSnapshot.docs.isEmpty) {
        print('   → Keine Nachrichten in Session, behalte Begrüßung');
        await _saveChatMessage(state.first);
        return;
      }

      print('   → ${messagesSnapshot.docs.length} Nachrichten gefunden');

      // Konvertiere zu ChatMessage
      final messages = messagesSnapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,
          text: data['text'] ?? '',
          isUser: data['isUser'] ?? false,
          // FIX: Timestamp korrekt aus Firestore lesen
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();

      // NUR ersetzen wenn mehr als nur Begrüßung vorhanden
      if (messages.length > 1) {
        state = messages;
        print('✅ Chat-Historie geladen und angezeigt');
      } else {
        print('   → Nur Begrüßung vorhanden, behalte aktuelle');
      }
    } catch (e) {
      print('⚠️ Fehler beim Laden der Historie: $e');
      // Nicht kritisch - Begrüßung bleibt
    } finally {
      _isLoadingHistory = false;
    }
  }

  /// Initialisiert AI Service (lazy - erst bei erster Nutzung)
  Future<void> _ensureAIInitialized() async {
    if (_isAIInitialized) return;

    try {
      print('🚀 Initialisiere AI Service...');
      await _aiService.initialize();
      _isAIInitialized = true;
      print('✅ AI Service bereit');
    } catch (e) {
      print('❌ Fehler bei AI-Initialisierung: $e');
      rethrow;
    }
  }

  /// NEU: Erstellt oder holt aktive Session
  Future<String> _getOrCreateSession() async {
    if (_currentSessionId != null) {
      return _currentSessionId!;
    }

    try {
      // Prüfe ob aktive Session existiert
      final sessionSnapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (sessionSnapshot.docs.isNotEmpty) {
        _currentSessionId = sessionSnapshot.docs.first.id;
        print('✅ Aktive Session gefunden: $_currentSessionId');
      } else {
        // Neue Session erstellen
        // FIX: Nutze lokale Zeit statt serverTimestamp (verhindert UTC-Zeitstempel-Bug)
        final sessionDoc = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('children')
            .doc(_childId)
            .collection('tutor_sessions')
            .add({
          'childId': _childId,
          'startedAt': Timestamp.fromDate(DateTime.now()),
          'status': 'active',
          'messageCount': 0,
        });
        _currentSessionId = sessionDoc.id;
        print('✅ Neue Session erstellt: $_currentSessionId');
      }

      return _currentSessionId!;
    } catch (e) {
      print('❌ Fehler bei Session-Erstellung: $e');
      rethrow;
    }
  }

  /// Sendet eine Nachricht an den Tutor
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    // Stelle sicher dass AI bereit ist
    if (!_isAIInitialized) {
      try {
        await _ensureAIInitialized();
      } catch (e) {
        // Fehler-Nachricht
        final errorMessage = ChatMessage.tutor(
          'Entschuldigung, ich hatte Probleme beim Starten. Versuch es gleich nochmal! 😊',
        );
        state = [...state, errorMessage];
        return;
      }
    }

    // User-Nachricht hinzufügen
    final userMessage = ChatMessage.user(text);
    state = [...state, userMessage];

    // In Firestore speichern (ohne zu warten)
    _saveChatMessage(userMessage);

    // Lade-Animation hinzufügen
    state = [...state, ChatMessage.loading()];

    try {
      // Antwort von Firebase AI holen
      final response = await _aiService.sendTutorMessage(
        child: child,
        userMessage: text,
        conversationHistory: state.where((m) => !m.isLoading).toList(),
      );

      // Tutor-Antwort erstellen
      final tutorMessage = ChatMessage.tutor(response);

      // Lade-Animation entfernen und Tutor-Antwort hinzufügen
      state = [
        ...state.where((m) => !m.isLoading),
        tutorMessage,
      ];

      // Tutor-Antwort in Firestore speichern
      _saveChatMessage(tutorMessage);
    } catch (e) {
      print('❌ Fehler beim Senden der Nachricht: $e');

      // Fehler-Nachricht
      final errorMessage = ChatMessage.tutor(
        'Ups, da ist etwas schiefgelaufen. Versuch es nochmal! 😅',
      );

      // Lade-Animation entfernen und Fehler-Nachricht hinzufügen
      state = [
        ...state.where((m) => !m.isLoading),
        errorMessage,
      ];

      // Fehler auch speichern
      _saveChatMessage(errorMessage);
    }
  }

  /// Speichert eine Nachricht in Firestore (fire-and-forget)
  /// FIX: Nutzt lokale Zeit statt serverTimestamp (verhindert UTC-Zeitstempel-Bug)
  /// FIX: Speichert NUR noch in tutor_sessions (nicht mehr in tutor_chat)
  Future<void> _saveChatMessage(ChatMessage message) async {
    if (message.isLoading) return;

    try {
      // FIX: Lokale Zeit statt FieldValue.serverTimestamp() – verhindert UTC-Bug
      final messageData = {
        'text': message.text,
        'isUser': message.isUser,
        'timestamp': Timestamp.fromDate(DateTime.now()),
      };

      // Session holen oder erstellen
      final sessionId = await _getOrCreateSession();

      // In Session speichern (permanent für Eltern)
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(sessionId)
          .collection('messages')
          .add(messageData);

      // Session-Counter erhöhen
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(sessionId)
          .update({
        'messageCount': FieldValue.increment(1),
      });

      // Wenn erste User-Nachricht: Thema + firstQuestion speichern
      if (message.isUser) {
        final sessionDoc = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('children')
            .doc(_childId)
            .collection('tutor_sessions')
            .doc(sessionId)
            .get();

        final sessionData = sessionDoc.data();
        final hasFirstQuestion = sessionData?['firstQuestion'] != null;

        if (!hasFirstQuestion) {
          final topic = _detectTopic(message.text);
          await _firestore
              .collection('users')
              .doc(_userId)
              .collection('children')
              .doc(_childId)
              .collection('tutor_sessions')
              .doc(sessionId)
              .update({
            'firstQuestion': message.text,
            'detectedTopic': topic,
          });
          print('🎯 Thema erkannt: $topic');
        }
      }

    } catch (e) {
      print('⚠️ Fehler beim Speichern: $e');
      // Nicht kritisch
    }
  }

  /// Erkennt das Thema aus dem Text
  String _detectTopic(String text) {
    final q = text.toLowerCase();
    if (q.contains('mathe') || q.contains('rechnen') || q.contains('plus') ||
        q.contains('minus') || q.contains('mal') || q.contains('geteilt') ||
        q.contains('bruch') || q.contains('prozent') || q.contains('zahl')) {
      return 'Mathematik';
    }
    if (q.contains('deutsch') || q.contains('grammatik') ||
        q.contains('rechtschreibung') || q.contains('wort') ||
        q.contains('satz') || q.contains('adjektiv') || q.contains('verb')) {
      return 'Deutsch';
    }
    if (q.contains('englisch') || q.contains('english') ||
        q.contains('past') || q.contains('present') || q.contains('verb')) {
      return 'Englisch';
    }
    if (q.contains('sachkunde') || q.contains('natur') ||
        q.contains('pflanzen') || q.contains('tiere') || q.contains('wetter')) {
      return 'Sachkunde';
    }
    return 'Allgemein';
  }

  /// Schließt die aktuelle Session ab (session-basiert)
  /// FIX: Löscht NICHT mehr tutor_chat – Session bleibt für Eltern erhalten
  /// Wird aufgerufen bei: Kind-Wechsel, Logout, App-Start (neue Session)
  Future<void> completeCurrentSession() async {
    if (_currentSessionId == null) return;

    print('🏁 Schließe Session ab: $_currentSessionId');

    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(_currentSessionId)
          .update({
        'status': 'completed',
        'endedAt': Timestamp.fromDate(DateTime.now()),
      });

      _currentSessionId = null;
      print('✅ Session abgeschlossen');
    } catch (e) {
      print('❌ Fehler beim Abschließen der Session: $e');
    }
  }

  /// Löscht den Chat und startet neue Session
  /// FIX: Löscht NICHT mehr tutor_chat – nur Session wird abgeschlossen
  /// und eine neue gestartet. Eltern-Historie bleibt vollständig erhalten.
  Future<void> clearChat() async {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    print('🔄 Starte neue Chat-Session für ${child.name}...');

    try {
      // Aktuelle Session abschließen
      await completeCurrentSession();

      // Neue Begrüßung
      final welcomeMessage = ChatMessage.tutor(
        'Hallo ${child.name}! 👋 Ich bin **Lerndex**, dein persönlicher Lernbegleiter! 🎓 Ich helfe dir bei allen Fragen zu Mathe, Deutsch, Englisch und anderen Schulfächern. Was möchtest du heute lernen? 📚✨',
      );

      state = [welcomeMessage];

      // Begrüßung in neuer Session speichern (erstellt automatisch neue Session)
      await _saveChatMessage(welcomeMessage);

      print('✅ Neue Session gestartet');
    } catch (e) {
      print('❌ Fehler beim Session-Reset: $e');
    }
  }
}

/// Provider für den Firebase AI Service (Singleton)
final firebaseAIServiceProvider = Provider<FirebaseAIService>((ref) {
  return FirebaseAIService();
});

/// 🎯 FAMILY PROVIDER - Ein Chat pro Kind!
final tutorProviderFamily = StateNotifierProvider.family<TutorNotifier, List<ChatMessage>, String>(
      (ref, childId) {
    final service = ref.watch(firebaseAIServiceProvider);
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) {
      throw Exception('User nicht eingeloggt');
    }

    return TutorNotifier(service, ref, childId, user.uid);
  },
);

/// 🎯 CONVENIENCE PROVIDER - Automatisch für aktives Kind
final tutorProvider = Provider<StateNotifierProvider<TutorNotifier, List<ChatMessage>>?>((ref) {
  final activeChild = ref.watch(activeChildProvider);

  if (activeChild == null) {
    return null;
  }

  return tutorProviderFamily(activeChild.id);
});