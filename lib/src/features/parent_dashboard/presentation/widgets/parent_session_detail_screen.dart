import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/tutor_chat_cleanup_service.dart';
import '../../../../shared/widgets/message_bubble.dart';
import '../../../tutor/domain/chat_message.dart';
import 'content_flag_banner.dart';

// ============================================================================
// PARENT SESSION DETAIL
// Eltern-Ansicht eines Tutor-Gesprächs mit Löschen-Button und Flag-Banner
// ============================================================================

class ParentSessionDetailScreen extends StatelessWidget {
  final String sessionId;
  final String userId;
  final String childId;
  final String topic;
  final DateTime? startedAt;
  final String childName;
  final String? contentFlag;

  const ParentSessionDetailScreen({
    super.key,
    required this.sessionId,
    required this.userId,
    required this.childId,
    required this.topic,
    required this.childName,
    this.startedAt,
    this.contentFlag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(topic),
            if (startedAt != null)
              Text(
                _formatFullDate(startedAt!),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        // ✅ Immer Lerndex-Lila – unabhängig vom Fach
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Gespräch löschen',
            onPressed: () => _deleteFromDetail(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (contentFlag != null) ContentFlagBanner(flag: contentFlag!),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('children')
                  .doc(childId)
                  .collection('tutor_sessions')
                  .doc(sessionId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Keine Nachrichten in dieser Session'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final msg = docs[i].data() as Map<String, dynamic>;
                    final isUser = msg['isUser'] as bool? ?? false;
                    final text = msg['text'] as String? ?? '';
                    final timestamp =
                        (msg['timestamp'] as Timestamp?)?.toDate() ??
                        DateTime.now();

                    return MessageBubble(
                      message: ChatMessage(
                        id: docs[i].id,
                        text: text,
                        isUser: isUser,
                        timestamp: timestamp,
                      ),
                      childName: childName,
                      topicColor: Colors.deepPurple,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromDetail(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Gespräch löschen?'),
          ],
        ),
        content: const Text(
          'Dieses Gespräch wird dauerhaft gelöscht – '
          'sowohl im Eltern- als auch im Schülerdashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final tutorChatCleanupService = TutorChatCleanupService();
    await tutorChatCleanupService.deleteSession(
      userId: userId,
      childId: childId,
      sessionId: sessionId,
    );

    if (context.mounted) Navigator.pop(context);
  }

  String _formatFullDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} Uhr';

    if (dateOnly == today) return 'Heute, $timeStr';
    if (dateOnly == yesterday) return 'Gestern, $timeStr';
    return '${date.day}.${date.month}.${date.year}, $timeStr';
  }
}
