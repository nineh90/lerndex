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
  Future<void> _loadChatHistoryInBackground() async {
    if (_isLoadingHistory) return;
    _isLoadingHistory = true;

    try {
      print('📚 Lade Chat-Historie für Kind $_childId im Hintergrund...');

      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_chat')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      if (snapshot.docs.isEmpty) {
        print('   → Keine Historie gefunden, behalte Begrüßung');
        // Begrüßung in Firestore speichern
        await _saveChatMessage(state.first);
        return;
      }

      print('   → ${snapshot.docs.length} Nachrichten gefunden');

      // Konvertiere zu ChatMessage (in richtiger Reihenfolge)
      final messages = snapshot.docs.reversed.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,  // ✅ Verwende Firestore Document ID
          text: data['text'] ?? '',
          isUser: data['isUser'] ?? false,
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
  Future<void> _saveChatMessage(ChatMessage message) async {
    if (message.isLoading) return;

    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_chat')
          .add({
        'text': message.text,
        'isUser': message.isUser,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('⚠️ Fehler beim Speichern: $e');
      // Nicht kritisch
    }
  }

  /// Löscht den Chat (für Neustart)
  Future<void> clearChat() async {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    print('🗑️ Lösche Chat für ${child.name}...');

    try {
      // Lösche alle Nachrichten aus Firestore
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_chat')
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      print('✅ Firestore Chat gelöscht');

      // Neue Begrüßung
      final welcomeMessage = ChatMessage.tutor(
        'Hallo ${child.name}! 👋 Ich bin **Lerndex**, dein persönlicher Lernbegleiter! 🎓 Ich helfe dir bei allen Fragen zu Mathe, Deutsch, Englisch und anderen Schulfächern. Was möchtest du heute lernen? 📚✨',
      );

      state = [welcomeMessage];

      // Begrüßung speichern
      await _saveChatMessage(welcomeMessage);

      print('✅ Chat zurückgesetzt');
    } catch (e) {
      print('❌ Fehler beim Löschen: $e');
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