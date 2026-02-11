import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../tutor/domain/chat_message.dart';

/// 💬 CHAT-HISTORIE FÜR ELTERN
/// Zeigt alle Tutor-Gespräche des Kindes chronologisch an
class TutorHistoryScreen extends ConsumerWidget {
  final ChildModel child;

  const TutorHistoryScreen({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Nicht angemeldet')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${child.name} - Tutor-Gespräche'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('children')
            .doc(child.id)
            .collection('tutor_chat')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine Gespräche',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${child.name} hat noch nicht mit dem Tutor gechattet',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          // Gruppiere Nachrichten nach Datum und Konversationen
          final groupedMessages = _groupMessagesByDateAndConversation(
            snapshot.data!.docs,
          );

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groupedMessages.length,
            itemBuilder: (context, index) {
              final dateGroup = groupedMessages[index];
              return _DateGroup(
                date: dateGroup['date'] as DateTime,
                conversations: dateGroup['conversations'] as List<ConversationGroup>,
                childName: child.name,
              );
            },
          );
        },
      ),
    );
  }

  /// Gruppiert Nachrichten nach Datum und erkennt Konversationen
  List<Map<String, dynamic>> _groupMessagesByDateAndConversation(
      List<QueryDocumentSnapshot> docs,
      ) {
    final Map<String, List<ChatMessage>> messagesByDate = {};

    // Gruppiere nach Datum
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final message = ChatMessage(
        id: doc.id,
        text: data['text'] ?? '',
        isUser: data['isUser'] ?? false,
        timestamp: (data['timestamp'] as Timestamp).toDate(),
      );

      final dateKey = _getDateKey(message.timestamp);
      messagesByDate[dateKey] ??= [];
      messagesByDate[dateKey]!.add(message);
    }

    // Konvertiere zu sortierter Liste und erkenne Konversationen
    final result = <Map<String, dynamic>>[];

    final sortedDates = messagesByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Neueste zuerst

    for (var dateKey in sortedDates) {
      final messages = messagesByDate[dateKey]!;
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp)); // Älteste zuerst innerhalb des Tages

      // Erkenne Konversationen (Pause > 15 Minuten = neue Konversation)
      final conversations = _detectConversations(messages);

      result.add({
        'date': DateTime.parse(dateKey),
        'conversations': conversations,
      });
    }

    return result;
  }

  /// Erkennt separate Konversationen basierend auf Zeitabständen
  List<ConversationGroup> _detectConversations(List<ChatMessage> messages) {
    if (messages.isEmpty) return [];

    final conversations = <ConversationGroup>[];
    List<ChatMessage> currentConversation = [];
    DateTime? lastMessageTime;

    for (var message in messages) {
      if (lastMessageTime != null) {
        final gap = message.timestamp.difference(lastMessageTime);

        // Neue Konversation wenn Pause > 15 Minuten
        if (gap.inMinutes > 15 && currentConversation.isNotEmpty) {
          conversations.add(ConversationGroup(messages: List.from(currentConversation)));
          currentConversation.clear();
        }
      }

      currentConversation.add(message);
      lastMessageTime = message.timestamp;
    }

    // Letzte Konversation hinzufügen
    if (currentConversation.isNotEmpty) {
      conversations.add(ConversationGroup(messages: currentConversation));
    }

    return conversations;
  }

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Repräsentiert eine Konversation (mehrere zusammenhängende Nachrichten)
class ConversationGroup {
  final List<ChatMessage> messages;

  ConversationGroup({required this.messages});

  DateTime get startTime => messages.first.timestamp;
  DateTime get endTime => messages.last.timestamp;

  int get messageCount => messages.length;

  Duration get duration => endTime.difference(startTime);

  // Erste Frage des Kindes finden
  String get firstQuestion {
    final firstUserMessage = messages.firstWhere(
          (m) => m.isUser,
      orElse: () => messages.first,
    );
    return firstUserMessage.text;
  }

  // Erkenne Thema aus der ersten Frage (einfache Heuristik)
  String get detectedTopic {
    final question = firstQuestion.toLowerCase();

    if (question.contains('mathe') || question.contains('rechnen') ||
        question.contains('plus') || question.contains('minus') ||
        question.contains('mal') || question.contains('geteilt') ||
        question.contains('bruch') || question.contains('prozent')) {
      return 'Mathematik';
    }

    if (question.contains('deutsch') || question.contains('grammatik') ||
        question.contains('rechtschreibung') || question.contains('wort') ||
        question.contains('satz') || question.contains('adjektiv')) {
      return 'Deutsch';
    }

    if (question.contains('englisch') || question.contains('english') ||
        question.contains('past') || question.contains('present') ||
        question.contains('verb')) {
      return 'Englisch';
    }

    if (question.contains('sachkunde') || question.contains('natur') ||
        question.contains('pflanzen') || question.contains('tiere')) {
      return 'Sachkunde';
    }

    return 'Allgemein';
  }

  // Icon basierend auf Thema
  IconData get topicIcon {
    switch (detectedTopic) {
      case 'Mathematik':
        return Icons.calculate;
      case 'Deutsch':
        return Icons.menu_book;
      case 'Englisch':
        return Icons.language;
      case 'Sachkunde':
        return Icons.science;
      default:
        return Icons.chat;
    }
  }

  // Farbe basierend auf Thema
  Color get topicColor {
    switch (detectedTopic) {
      case 'Mathematik':
        return Colors.orange;
      case 'Deutsch':
        return Colors.red;
      case 'Englisch':
        return Colors.blue;
      case 'Sachkunde':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // 🌟 Zukünftig: XP/Sterne berechnen basierend auf Gesprächslänge
  int get potentialXP {
    // 1 XP pro Nachricht, max 10 XP pro Gespräch
    return (messageCount * 1).clamp(0, 10);
  }

  int get potentialStars {
    // 1 Stern pro 5 Minuten Gespräch
    return (duration.inMinutes ~/ 5).clamp(0, 5);
  }
}

/// Widget für eine Datums-Gruppe
class _DateGroup extends StatelessWidget {
  final DateTime date;
  final List<ConversationGroup> conversations;
  final String childName;

  const _DateGroup({
    required this.date,
    required this.conversations,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Datums-Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                _formatDate(date),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${conversations.length} ${conversations.length == 1 ? "Gespräch" : "Gespräche"})',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),

        // Konversationen
        ...conversations.asMap().entries.map((entry) {
          final index = entry.key;
          final conversation = entry.value;
          return _ConversationCard(
            conversation: conversation,
            index: index + 1,
            childName: childName,
          );
        }),

        const SizedBox(height: 24),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Heute';
    } else if (dateOnly == yesterday) {
      return 'Gestern';
    } else {
      final weekday = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][date.weekday - 1];
      return '$weekday, ${date.day}.${date.month}.${date.year}';
    }
  }
}

/// Widget für eine einzelne Konversation
class _ConversationCard extends StatelessWidget {
  final ConversationGroup conversation;
  final int index;
  final String childName;

  const _ConversationCard({
    required this.conversation,
    required this.index,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ConversationDetailScreen(
                conversation: conversation,
                childName: childName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header mit Zeit und Thema
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: conversation.topicColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      conversation.topicIcon,
                      color: conversation.topicColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conversation.detectedTopic,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: conversation.topicColor,
                          ),
                        ),
                        Text(
                          '${_formatTime(conversation.startTime)} - ${_formatDuration(conversation.duration)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Nachrichtenzähler
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[700]),
                        const SizedBox(width: 4),
                        Text(
                          '${conversation.messageCount}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Preview der ersten Frage
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        conversation.firstQuestion,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🌟 Zukünftige Belohnungs-Preview (ausgegraut)
              const SizedBox(height: 8),
              Row(
                children: [
                  _FutureBadge(
                    icon: Icons.flash_on,
                    label: '+${conversation.potentialXP} XP',
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  _FutureBadge(
                    icon: Icons.star,
                    label: '+${conversation.potentialStars} ⭐',
                    color: Colors.amber,
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return '< 1 Min';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes} Min';
    } else {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '${hours}h ${minutes}min';
    }
  }
}

/// Badge für zukünftige Belohnungen
class _FutureBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FutureBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.4, // Ausgegraut = noch nicht aktiv
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail-Ansicht einer Konversation
class _ConversationDetailScreen extends StatelessWidget {
  final ConversationGroup conversation;
  final String childName;

  const _ConversationDetailScreen({
    required this.conversation,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gespräch - ${conversation.detectedTopic}'),
        backgroundColor: conversation.topicColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Info-Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: conversation.topicColor.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(conversation.topicIcon, color: conversation.topicColor),
                    const SizedBox(width: 8),
                    Text(
                      conversation.detectedTopic,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: conversation.topicColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatTime(conversation.startTime)} - ${_formatTime(conversation.endTime)}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(conversation.duration),
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Chat-Nachrichten
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: conversation.messages.length,
              itemBuilder: (context, index) {
                final message = conversation.messages[index];
                return _MessageBubble(
                  message: message,
                  childName: childName,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return '< 1 Min';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes} Min';
    } else {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '${hours}h ${minutes}min';
    }
  }
}

/// Chat-Bubble für Nachrichten
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String childName;

  const _MessageBubble({
    required this.message,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
        message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple,
              child: const Icon(Icons.school, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isUser ? Colors.blue[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.isUser ? childName : 'Lerndex Tutor',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.text,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Text(
                childName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}