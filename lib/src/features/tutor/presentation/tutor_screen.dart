import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../domain/chat_message.dart';
import 'tutor_provider.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../learning_time/learning_time_tracker.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/data/reward_service.dart';

/// Chat-Screen mit dem KI-Tutor
class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key});

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  LearningTimeTracker? _timeTracker;

  @override
  void initState() {
    super.initState();

    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;

    if (child != null && user != null) {
      _timeTracker = LearningTimeTracker(
        userId: user.uid,
        childId: child.id,
      );
      _timeTracker!.startTracking();
      print('⏱️ Tutor: Zeit-Tracking gestartet');
    }
  }

  @override
  void dispose() async {
    if (_timeTracker != null) {
      _timeTracker!.stopTracking();
      print('⏹️ Tutor: Stoppe Zeit-Tracking bei ${_timeTracker!.trackedSeconds} Sekunden');

      try {
        await _timeTracker!.saveTime();
        print('✅ Tutor: Lernzeit gespeichert');

        final child = ref.read(activeChildProvider);
        final user = ref.read(authStateChangesProvider).value;

        if (child != null && user != null) {
          final xpService = ref.read(xpServiceProvider);

          final newStreak = await xpService.updateStreak(
            userId: user.uid,
            childId: child.id,
          );
          print('✅ Tutor: Streak aktualisiert → $newStreak Tage');

          final rewardService = ref.read(rewardServiceProvider);
          ChildModel? updatedChild = await xpService.getChild(
            userId: user.uid,
            childId: child.id,
          );

          if (updatedChild != null) {
            updatedChild = updatedChild.copyWith(streak: newStreak);

            final unlockedRewards = await rewardService.checkAndApproveRewards(
              userId: user.uid,
              child: updatedChild,
            );

            if (unlockedRewards.isNotEmpty) {
              print('🎁 Tutor: ${unlockedRewards.length} Belohnungen freigeschaltet!');
            }
          }
        }
      } catch (e) {
        print('❌ Fehler beim Speichern der Tutor-Lernzeit: $e');
      }
      _timeTracker!.dispose();
    }

    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final providerInstance = ref.read(tutorProvider);
    if (providerInstance != null) {
      ref.read(providerInstance.notifier).sendMessage(text);
    }
    _messageController.clear();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final providerInstance = ref.watch(tutorProvider);
    final messages = providerInstance != null
        ? ref.watch(providerInstance)
        : <ChatMessage>[];
    final child = ref.watch(activeChildProvider);

    if (child == null) {
      return const Scaffold(
        body: Center(child: Text('Kein Kind ausgewählt')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎓 Lerndex Tutor'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Chat löschen?'),
                  content: const Text(
                      'Möchtest du den Chat wirklich löschen und neu starten?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final providerInstance = ref.read(tutorProvider);
                        if (providerInstance != null) {
                          ref.read(providerInstance.notifier).clearChat();
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Löschen'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Chat neu starten',
          ),
        ],
      ),
      body: Column(
        children: [
          // Info-Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Frag mich alles über Mathe, Deutsch, Englisch und mehr!',
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Chat-Nachrichten
          Expanded(
            child: messages.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.smart_toy,
                    size: 80,
                    color: Colors.deepPurple.shade200,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hallo ${child.name}! 👋',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ich bin dein persönlicher Lernbegleiter.\nStell mir eine Frage!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return _MessageBubble(message: message);
              },
            ),
          ),

          // ── Eingabe-Leiste ──────────────────────────────────────────────
          // FIX 1: SafeArea (nur bottom) → kein Überlappen mit Home-Indikator
          SafeArea(
            left: false,
            right: false,
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    // FIX 2: maxLines: null + keyboardType multiline → Zeilenumbruch
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Stell mir eine Frage...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Senden-Button unten ausgerichtet bei mehrzeiligem Text
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: FloatingActionButton(
                      onPressed: _sendMessage,
                      backgroundColor: Colors.deepPurple,
                      mini: true,
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MESSAGE BUBBLE
// ============================================================================

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    // FIX 3: Lade-Zustand zeigt "Tutor denkt nach..." statt leerer Blase
    if (message.isLoading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Tutor denkt nach...',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.black54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.deepPurple : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: isUser
              ? Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
            ),
          )
              : MarkdownBody(
            data: message.text,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(fontSize: 15, color: Colors.black87),
              strong: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}