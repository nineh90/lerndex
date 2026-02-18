import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../tutor/domain/chat_message.dart';

/// 💬 CHAT-HISTORIE FÜR ELTERN
/// Zeigt alle Tutor-Gespräche des Kindes chronologisch an
/// FIX 1: Liest aus tutor_sessions statt tutor_chat
/// FIX 2: Zeitstempel-Bug behoben (Kalender-Tag-Vergleich)
/// FIX 3: Filter nach Thema hinzugefügt
class TutorHistoryScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const TutorHistoryScreen({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<TutorHistoryScreen> createState() => _TutorHistoryScreenState();
}

class _TutorHistoryScreenState extends ConsumerState<TutorHistoryScreen> {
  // FIX 3: Filter-State
  String _filterTopic = 'Alle';
  final List<String> _topics = [
    'Alle',
    'Mathematik',
    'Deutsch',
    'Englisch',
    'Sachkunde',
    'Allgemein',
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Nicht angemeldet')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.child.name} - Tutor-Gespräche'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // FIX 3: Filter-Leiste
          _buildFilterBar(),
          // Session-Liste
          Expanded(
            child: _buildSessionList(user.uid),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 52,
      color: Colors.deepPurple.shade50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: _topics.map((topic) {
          final selected = topic == _filterTopic;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(topic),
              selected: selected,
              onSelected: (_) => setState(() => _filterTopic = topic),
              selectedColor: Colors.deepPurple,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.deepPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSessionList(String userId) {
    // FIX 1: Liest jetzt aus tutor_sessions statt tutor_chat
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(widget.child.id)
          .collection('tutor_sessions')
          .orderBy('startedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Fehler: ${snapshot.error}'));
        }

        final allDocs = snapshot.data?.docs ?? [];

        // FIX 3: Filter anwenden
        final filteredDocs = _filterTopic == 'Alle'
            ? allDocs
            : allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final topic = data['detectedTopic'] as String? ?? 'Allgemein';
          // Normalisiere Mathe/Mathematik
          final normalizedTopic = _normalizeTopic(topic);
          return normalizedTopic == _filterTopic;
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  _filterTopic == 'Alle'
                      ? 'Noch keine Gespräche'
                      : 'Keine Gespräche zu "$_filterTopic"',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                if (_filterTopic == 'Alle')
                  Text(
                    '${widget.child.name} hat noch nicht mit dem Tutor gechattet',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
              ],
            ),
          );
        }

        // Gruppiere Sessions nach Datum
        final groupedSessions = _groupSessionsByDate(filteredDocs);

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupedSessions.length,
          itemBuilder: (context, index) {
            final dateGroup = groupedSessions[index];
            return _SessionDateGroup(
              date: dateGroup['date'] as DateTime,
              sessions: dateGroup['sessions'] as List<QueryDocumentSnapshot>,
              child: widget.child,
              userId: userId,
            );
          },
        );
      },
    );
  }

  /// Normalisiert Themen-Strings (z.B. "Mathe" → "Mathematik")
  String _normalizeTopic(String topic) {
    switch (topic.toLowerCase()) {
      case 'mathe':
      case 'mathematik':
        return 'Mathematik';
      case 'deutsch':
        return 'Deutsch';
      case 'englisch':
      case 'english':
        return 'Englisch';
      case 'sachkunde':
        return 'Sachkunde';
      default:
        return 'Allgemein';
    }
  }

  /// Gruppiert Sessions nach Kalender-Datum
  List<Map<String, dynamic>> _groupSessionsByDate(
      List<QueryDocumentSnapshot> docs) {
    final Map<String, List<QueryDocumentSnapshot>> byDate = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      // FIX 2: Kalender-Tag-Vergleich für korrekte Datums-Gruppierung
      final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
      if (startedAt == null) continue;

      final dateKey =
          '${startedAt.year}-${startedAt.month.toString().padLeft(2, '0')}-${startedAt.day.toString().padLeft(2, '0')}';
      byDate[dateKey] ??= [];
      byDate[dateKey]!.add(doc);
    }

    final sortedKeys = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return sortedKeys.map((key) {
      final parts = key.split('-');
      return {
        'date': DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
        'sessions': byDate[key]!,
      };
    }).toList();
  }
}

// ============================================================================
// DATUMS-GRUPPE
// ============================================================================

class _SessionDateGroup extends StatelessWidget {
  final DateTime date;
  final List<QueryDocumentSnapshot> sessions;
  final ChildModel child;
  final String userId;

  const _SessionDateGroup({
    required this.date,
    required this.sessions,
    required this.child,
    required this.userId,
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
                '(${sessions.length} ${sessions.length == 1 ? "Gespräch" : "Gespräche"})',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        // Session-Karten
        ...sessions.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _SessionCard(
            sessionId: doc.id,
            data: data,
            child: child,
            userId: userId,
          );
        }),

        const SizedBox(height: 24),
      ],
    );
  }

  // FIX 2: Korrekte Datums-Formatierung mit Kalender-Tag-Vergleich
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) return 'Heute';
    if (dateOnly == yesterday) return 'Gestern';

    final weekday = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][date.weekday - 1];
    return '$weekday, ${date.day}.${date.month}.${date.year}';
  }
}

// ============================================================================
// SESSION-KARTE
// ============================================================================

class _SessionCard extends StatelessWidget {
  final String sessionId;
  final Map<String, dynamic> data;
  final ChildModel child;
  final String userId;

  const _SessionCard({
    required this.sessionId,
    required this.data,
    required this.child,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final rawTopic = data['detectedTopic'] as String? ?? 'Allgemein';
    final topic = _normalizeTopic(rawTopic);
    final msgCount = data['messageCount'] as int? ?? 0;
    final status = data['status'] as String? ?? 'active';
    final firstQuestion = data['firstQuestion'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SessionDetailScreen(
              sessionId: sessionId,
              userId: userId,
              childId: child.id,
              topic: topic,
              startedAt: startedAt,
              childName: child.name,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _topicColor(topic).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _topicIcon(topic),
                      color: _topicColor(topic),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _topicColor(topic),
                          ),
                        ),
                        if (startedAt != null)
                          Text(
                            // FIX 2: Zeigt nur Uhrzeit (Datum kommt vom Datums-Header)
                            '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')} Uhr',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                  // Status-Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$msgCount Nachrichten',
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'completed'
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status == 'completed' ? 'Abgeschlossen' : 'Aktiv',
                          style: TextStyle(
                            fontSize: 10,
                            color: status == 'completed'
                                ? Colors.green
                                : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Erste Frage Preview
              if (firstQuestion != null && firstQuestion.isNotEmpty) ...[
                const SizedBox(height: 12),
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
                          firstQuestion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                          TextStyle(fontSize: 14, color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _normalizeTopic(String topic) {
    switch (topic.toLowerCase()) {
      case 'mathe':
      case 'mathematik':
        return 'Mathematik';
      case 'deutsch':
        return 'Deutsch';
      case 'englisch':
      case 'english':
        return 'Englisch';
      case 'sachkunde':
        return 'Sachkunde';
      default:
        return 'Allgemein';
    }
  }

  Color _topicColor(String topic) {
    switch (topic) {
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

  IconData _topicIcon(String topic) {
    switch (topic) {
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
}

// ============================================================================
// SESSION DETAIL
// ============================================================================

class _SessionDetailScreen extends StatelessWidget {
  final String sessionId;
  final String userId;
  final String childId;
  final String topic;
  final DateTime? startedAt;
  final String childName;

  const _SessionDetailScreen({
    required this.sessionId,
    required this.userId,
    required this.childId,
    required this.topic,
    required this.childName,
    this.startedAt,
  });

  @override
  Widget build(BuildContext context) {
    final topicColor = _topicColor(topic);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(topic),
            if (startedAt != null)
              Text(
                // FIX 2: Korrektes Datum im Detail-Screen
                _formatFullDate(startedAt!),
                style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: topicColor,
        foregroundColor: Colors.white,
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
              final timestamp = (msg['timestamp'] as Timestamp?)?.toDate();

              return _MessageBubble(
                isUser: isUser,
                text: text,
                timestamp: timestamp,
                childName: childName,
                topicColor: topicColor,
              );
            },
          );
        },
      ),
    );
  }

  // FIX 2: Vollständige Datums-Formatierung mit Kalender-Tag-Vergleich
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

  Color _topicColor(String topic) {
    switch (topic) {
      case 'Mathematik':
        return Colors.orange;
      case 'Deutsch':
        return Colors.red;
      case 'Englisch':
        return Colors.blue;
      case 'Sachkunde':
        return Colors.green;
      default:
        return Colors.deepPurple;
    }
  }
}

// ============================================================================
// MESSAGE BUBBLE
// ============================================================================

class _MessageBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  final DateTime? timestamp;
  final String childName;
  final Color topicColor;

  const _MessageBubble({
    required this.isUser,
    required this.text,
    required this.childName,
    required this.topicColor,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
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
                color: isUser ? Colors.blue[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? childName : 'Lerndex Tutor',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(fontSize: 14)),
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      // FIX 2: Nur Uhrzeit anzeigen (kein "heute X Uhr"-Bug)
                      '${timestamp!.hour.toString().padLeft(2, '0')}:${timestamp!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
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
}