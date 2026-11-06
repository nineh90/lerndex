import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/chat_message.dart';

/// Nachricht aus einem Dokument unter
/// `tutor_sessions/{sessionId}/messages/{messageId}`.
ChatMessage chatMessageFromFirestore(String id, Map<String, dynamic> data) {
  return ChatMessage(
    id: id,
    text: data['text'] as String? ?? '',
    isUser: data['isUser'] as bool? ?? false,
    timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    imageUrl: data['imageUrl'] as String?,
    excludeFromAi: data['excludeFromAi'] as bool? ?? false,
  );
}

/// Felder einer neuen Nachricht für Firestore.
Map<String, dynamic> chatMessageToFirestore(ChatMessage message) => {
  'text': message.text,
  'isUser': message.isUser,
  'timestamp': Timestamp.fromDate(DateTime.now()),
  if (message.imageUrl != null) 'imageUrl': message.imageUrl,
  if (message.excludeFromAi) 'excludeFromAi': true,
};
