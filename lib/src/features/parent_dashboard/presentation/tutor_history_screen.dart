import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../tutor/domain/chat_message.dart';
import '../../../services/tutor_chat_cleanup_service.dart';

/// 💬 CHAT-HISTORIE FÜR ELTERN
/// - Dynamische Topic-Filter (nur tatsächlich vorhandene Topics)
/// - Leere Sessions ausgeblendet (messageCount <= 1)
/// - Swipe-to-delete + Bestätigungs-Dialog
/// - Löschen-Button im Detail-Screen
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
  String _filterTopic = 'Alle';
  List<String> _availableTopics = ['Alle'];

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
        title: Text('${widget.child.name} – Gespräche'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Alle Gespräche löschen',
            onPressed: () => _confirmDeleteAll(context, user.uid),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildSessionList(user.uid)),
        ],
      ),
    );
  }

  // ── Filter-Leiste (dynamisch) ─────────────────────────────────────────────

  Widget _buildFilterBar() {
    if (_availableTopics.length <= 1) return const SizedBox.shrink();

    return Container(
      height: 52,
      color: Colors.deepPurple.shade50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: _availableTopics.map((topic) {
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

  // ── Session-Liste ─────────────────────────────────────────────────────────

  Widget _buildSessionList(String userId) {
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

        // Leere Sessions ausblenden
        final allDocs = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['messageCount'] as int? ?? 0) > 1;
        }).toList();

        // Dynamische Topics aus tatsächlichen Sessions
        final topicSet = <String>{};
        for (final doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final raw = data['detectedTopic'] as String? ?? 'Allgemein';
          topicSet.add(_normalizeTopic(raw));
        }
        final sortedTopics = [
          'Alle',
          ...topicSet.toList()..sort(),
        ];

        // State aktualisieren falls Topics sich geändert haben
        if (sortedTopics.join() != _availableTopics.join()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _availableTopics = sortedTopics;
                if (!sortedTopics.contains(_filterTopic)) {
                  _filterTopic = 'Alle';
                }
              });
            }
          });
        }

        // Filter anwenden
        final filteredDocs = _filterTopic == 'Alle'
            ? allDocs
            : allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final raw = data['detectedTopic'] as String? ?? 'Allgemein';
          return _normalizeTopic(raw) == _filterTopic;
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  _filterTopic == 'Alle'
                      ? 'Noch keine Gespräche'
                      : 'Keine Gespräche in "$_filterTopic"',
                  style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return _buildGroupedList(filteredDocs, userId);
      },
    );
  }

  Widget _buildGroupedList(List<QueryDocumentSnapshot> docs, String userId) {
    final Map<String, List<QueryDocumentSnapshot>> grouped = {};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final date = (data['startedAt'] as Timestamp?)?.toDate();
      final key = date != null ? _formatDate(date) : 'Unbekannt';
      grouped.putIfAbsent(key, () => []).add(doc);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Datums-Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value.length} ${entry.value.length == 1 ? "Gespräch" : "Gespräche"}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            // Swipeable Karten
            ...entry.value.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _buildSwipeableCard(
                context: context,
                doc: doc,
                data: data,
                userId: userId,
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSwipeableCard({
    required BuildContext context,
    required QueryDocumentSnapshot doc,
    required Map<String, dynamic> data,
    required String userId,
  }) {
    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text('Löschen',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDeleteSingle(context),
      onDismissed: (_) =>
          _deleteSession(userId: userId, sessionId: doc.id),
      child: _SessionCard(
        sessionId: doc.id,
        data: data,
        child: widget.child,
        userId: userId,
      ),
    );
  }

  // ── Löschen-Dialoge ───────────────────────────────────────────────────────

  Future<bool> _confirmDeleteSingle(BuildContext context) async {
    final result = await showDialog<bool>(
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
              'sowohl im Elterndashboard als auch im Schülerdashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child:
            const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _confirmDeleteAll(BuildContext context, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 8),
            Text('Alle Gespräche löschen?'),
          ],
        ),
        content: Text(
          'Alle Gespräche von ${widget.child.name} werden dauerhaft gelöscht. '
              'Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Alle löschen',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await tutorChatCleanupService.deleteAllSessionsForChild(
        userId: userId,
        childId: widget.child.id,
      );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e')),
        );
      }
    }
  }

  Future<void> _deleteSession({
    required String userId,
    required String sessionId,
  }) async {
    try {
      await tutorChatCleanupService.deleteSession(
        userId: userId,
        childId: widget.child.id,
        sessionId: sessionId,
      );
    } catch (e) {
      print('❌ Fehler beim Löschen der Session: $e');
    }
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) return 'Heute';
    if (dateOnly == yesterday) return 'Gestern';

    final weekday =
    ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][date.weekday - 1];
    return '$weekday, ${date.day}.${date.month}.${date.year}';
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
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _topicColor(topic).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_topicIcon(topic),
                        color: _topicColor(topic), size: 20),
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
                            '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')} Uhr',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
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
                          borderRadius: BorderRadius.circular(12),
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

              if (firstQuestion != null && firstQuestion.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
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
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '← Wischen zum Löschen',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
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
                _formatFullDate(startedAt!),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: topicColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Gespräch löschen',
            onPressed: () => _deleteFromDetail(context),
          ),
        ],
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
            child:
            const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

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
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                isUser ? childName : '🎓 Lerndex',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isUser ? Colors.deepPurple : topicColor,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color:
                isUser ? Colors.deepPurple.shade50 : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: isUser
                      ? Colors.deepPurple.shade100
                      : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(text,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${timestamp!.hour.toString().padLeft(2, '0')}:${timestamp!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}