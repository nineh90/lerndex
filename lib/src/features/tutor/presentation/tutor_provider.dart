import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/gemini_service.dart';
import '../domain/chat_message.dart';
import '../domain/tutor_config.dart';
import '../../auth/presentation/active_child_provider.dart';

/// Verwaltet den Chat-Zustand mit dem KI-Tutor
class TutorNotifier extends StateNotifier<List<ChatMessage>> {
  TutorNotifier(this._geminiService, this._ref) : super([]);

  final GeminiService _geminiService;
  final Ref _ref;
  bool _isInitialized = false;

  /// Initialisiert den Tutor mit Begrüßung
  Future<void> initialize() async {
    if (_isInitialized) return;

    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    try {
      // Gemini Service initialisieren
      await _geminiService.initialize(child);

      // Begrüßungsnachricht hinzufügen
      state = [
        ChatMessage.tutor(TutorConfig.getWelcomeMessage(child)),
      ];

      _isInitialized = true;
    } catch (e) {
      print('Fehler beim Initialisieren des Tutors: $e');
      state = [
        ChatMessage.tutor(
          'Hallo! Leider gab es ein Problem beim Starten. Bitte versuche es später nochmal. 😊',
        ),
      ];
    }
  }

  /// Sendet eine Nachricht an den Tutor
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // User-Nachricht hinzufügen
    final userMessage = ChatMessage.user(text);
    state = [...state, userMessage];

    // Lade-Animation hinzufügen
    state = [...state, ChatMessage.loading()];

    try {
      // Antwort von Gemini holen
      final response = await _geminiService.sendMessage(
        text,
        state.where((m) => !m.isLoading).toList(),
      );

      // Lade-Animation entfernen und Tutor-Antwort hinzufügen
      state = [
        ...state.where((m) => !m.isLoading),
        ChatMessage.tutor(response),
      ];
    } catch (e) {
      print('Fehler beim Senden der Nachricht: $e');

      // Lade-Animation entfernen und Fehler-Nachricht hinzufügen
      state = [
        ...state.where((m) => !m.isLoading),
        ChatMessage.tutor(
          'Ups, da ist etwas schiefgelaufen. Versuch es nochmal! 😅',
        ),
      ];
    }
  }

  /// Löscht den Chat (für Neustart)
  void clearChat() {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    state = [
      ChatMessage.tutor(TutorConfig.getWelcomeMessage(child)),
    ];
  }
}

/// Provider für den Gemini Service (Singleton)
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

/// Provider für den Tutor Chat
final tutorProvider = StateNotifierProvider<TutorNotifier, List<ChatMessage>>((ref) {
  final service = ref.watch(geminiServiceProvider);
  return TutorNotifier(service, ref);
});