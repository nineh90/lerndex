/// Repräsentiert eine Chat-Nachricht im Tutor
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;           // true = vom Kind, false = vom Tutor
  final DateTime timestamp;
  final bool isLoading;        // Zeigt Lade-Animation

  /// Remote-URL eines hochgeladenen Aufgabenblatt-Fotos (Firebase Storage).
  /// Wird in Firestore persistiert → Eltern können das Bild im Verlauf sehen.
  final String? imageUrl;

  /// Lokaler Pfad des gerade gewählten Fotos (nur In-Memory, für die sofortige
  /// Vorschau bevor der Upload fertig ist). Wird nicht persistiert.
  final String? localImagePath;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isLoading = false,
    this.imageUrl,
    this.localImagePath,
  });

  /// True wenn diese Nachricht ein Foto enthält (remote oder lokal)
  bool get hasImage =>
      (imageUrl != null && imageUrl!.isNotEmpty) ||
      (localImagePath != null && localImagePath!.isNotEmpty);

  /// Erstellt eine User-Nachricht
  factory ChatMessage.user(String text, {String? localImagePath}) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      localImagePath: localImagePath,
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
    String? imageUrl,
    String? localImagePath,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
      imageUrl: imageUrl ?? this.imageUrl,
      localImagePath: localImagePath ?? this.localImagePath,
    );
  }
}
