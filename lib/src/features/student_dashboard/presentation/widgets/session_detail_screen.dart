import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/auth/presentation/active_child_provider.dart';
import 'package:lerndex/src/features/tutor/presentation/tutor_provider.dart';
import 'package:lerndex/src/features/tutor/domain/chat_message.dart';
import 'package:lerndex/src/features/tutor/presentation/tutor_screen.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/shared/widgets/message_bubble.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';
// ============================================================================
// SESSION DETAIL – Nachrichtenanzeige (Schüler-Sicht)
// ============================================================================

class SessionDetailScreen extends ConsumerWidget {
  final String userId;
  final String childId;
  final String sessionId;
  final String topic;
  final DateTime? startedAt;

  const SessionDetailScreen({
    super.key,
    required this.userId,
    required this.childId,
    required this.sessionId,
    required this.topic,
    this.startedAt,
  });

  Future<void> _resumeSession(BuildContext context, WidgetRef ref) async {
    final activeChild = ref.read(activeChildProvider);
    if (activeChild == null || !context.mounted) return;

    ref.read(tutorResumeSessionIdProvider.notifier).state = sessionId;
    ref.invalidate(tutorProviderFamily(activeChild.id));
    ref.invalidate(tutorSessionXpProvider(activeChild.id));

    if (context.mounted) {
      // Pop detail screen first, then open tutor
      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TutorScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Beim Verlassen nicht weiter vorlesen
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(ttsControllerProvider.notifier).stop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(topic),
              if (startedAt != null)
                Text(
                  '${startedAt!.day}.${startedAt!.month}.${startedAt!.year}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          backgroundColor: AppColors.purple,
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _resumeSession(context, ref),
          backgroundColor: AppColors.purple,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Chat fortsetzen'),
        ),
        body: StreamBuilder<QuerySnapshot>(
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
              return const Center(child: Text('Keine Nachrichten'));
            }

            // Gleiche Darstellung wie im Chat: Formeln, Fotos, Vorlesen
            final child = ref.watch(activeChildProvider);
            final ttsState = ref.watch(ttsControllerProvider);
            final tts = ref.read(ttsControllerProvider.notifier);

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final msg = docs[i].data() as Map<String, dynamic>;
                final message = ChatMessage(
                  id: docs[i].id,
                  text: msg['text'] as String? ?? '',
                  isUser: msg['isUser'] as bool? ?? false,
                  timestamp:
                      (msg['timestamp'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
                  imageUrl: msg['imageUrl'] as String?,
                );
                final speaking = ttsState.isSpeakingId(message.id);
                return MessageBubble(
                  message: message,
                  childName: child?.name ?? '',
                  childSelectedAvatar: child?.selectedAvatar,
                  isSpeaking: speaking,
                  onSpeak: message.isUser
                      ? null
                      : () => speaking
                            ? tts.stop()
                            : tts.speakTutor(message.text, id: message.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
