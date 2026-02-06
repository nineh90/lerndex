/// Repräsentiert eine Chat-Nachricht im Tutor
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;           // true = vom Kind, false = vom Tutor
  final DateTime timestamp;
  final bool isLoading;        // Zeigt Lade-Animation

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLoading = false,
  });

  /// Erstellt eine User-Nachricht
  factory ChatMessage.user(String text) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
  }

  /// Erstellt eine Tutor-Nachricht
  factory ChatMessage.tutor(String text) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
    );
  }

  /// Erstellt eine Lade-Nachricht
  factory ChatMessage.loading() {
    return ChatMessage(
      id: 'loading',
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      isLoading: true,
    );
  }

  /// Kopie mit geänderten Werten
  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    bool? isLoading,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}