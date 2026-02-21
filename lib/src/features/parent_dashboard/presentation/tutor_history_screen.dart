import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../tutor/domain/chat_message.dart';
import '../../../services/tutor_chat_cleanup_service.dart';

/// 💬 CHAT-HISTORIE FÜR ELTERN
/// - Dynamische Topic-Filter (nur tatsächlich vorhandene Topics)
/// - ⚠️ / 🚨 Content-Flag-Badges für auffällige Gespräche
/// - Filterchip "⚠️ Auffällig" für schnellen Überblick
/// - Leere Sessions ausgeblendet (messageCount <= 1)
/// - Swipe-to-delete + Bestätigungs-Dialog
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

  // Sonderfilter: zeigt nur Sessions mit contentFlag
  bool _showFlaggedOnly = false;

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

  // ── Filter-Leiste ─────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    if (_availableTopics.length <= 1 && !_hasFlaggedSessions) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.deepPurple.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zeile 1: Fach-Filter
          if (_availableTopics.length > 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: _availableTopics.map((topic) {
                  final selected =
                      topic == _filterTopic && !_showFlaggedOnly;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(topic),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _filterTopic = topic;
                        _showFlaggedOnly = false;
                      }),
                      selectedColor: Colors.deepPurple,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.deepPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          // Zeile 2: Auffällig-Filter (nur wenn es flagged Sessions gibt)
          if (_hasFlaggedSessions)
            Padding(
              padding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 2),
              child: Row(
                children: [
                  // ⚠️ Chip
                  _FlagFilterChip(
                    label: '⚠️ Nicht-Schulthema',
                    flagValue: 'off_topic',
                    isSelected: _showFlaggedOnly && _filterTopic == 'off_topic',
                    onTap: () => setState(() {
                      if (_showFlaggedOnly && _filterTopic == 'off_topic') {
                        _showFlaggedOnly = false;
                        _filterTopic = 'Alle';
                      } else {
                        _showFlaggedOnly = true;
                        _filterTopic = 'off_topic';
                      }
                    }),
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  // 🚨 Chip
                  _FlagFilterChip(
                    label: '🚨 Bedenklich',
                    flagValue: 'critical',
                    isSelected: _showFlaggedOnly && _filterTopic == 'critical',
                    onTap: () => setState(() {
                      if (_showFlaggedOnly && _filterTopic == 'critical') {
                        _showFlaggedOnly = false;
                        _filterTopic = 'Alle';
                      } else {
                        _showFlaggedOnly = true;
                        _filterTopic = 'critical';
                      }
                    }),
                    color: Colors.red,
                  ),
                ],
              ),
            ),

          const Divider(height: 1),
        ],
      ),
    );
  }

  // Wird gesetzt sobald wir wissen, ob es flagged Sessions gibt
  bool _hasFlaggedSessions = false;

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

        // Prüfen ob es irgendwelche flagged Sessions gibt
        final hasFlagged = allDocs.any((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['contentFlag'] != null;
        });
        if (hasFlagged != _hasFlaggedSessions) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _hasFlaggedSessions = hasFlagged);
          });
        }

        // Dynamische Topics aus tatsächlichen Sessions
        final topicSet = <String>{};
        for (final doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final raw = data['detectedTopic'] as String? ?? 'Allgemein';
          topicSet.add(_normalizeTopic(raw));
        }
        final sortedTopics = ['Alle', ...topicSet.toList()..sort()];

        if (sortedTopics.join() != _availableTopics.join()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _availableTopics = sortedTopics;
                if (!sortedTopics.contains(_filterTopic) &&
                    !_showFlaggedOnly) {
                  _filterTopic = 'Alle';
                }
              });
            }
          });
        }

        // Filter anwenden
        List<QueryDocumentSnapshot> filteredDocs;

        if (_showFlaggedOnly) {
          // Flag-Filter: zeige nur Sessions mit dem gewählten contentFlag
          filteredDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['contentFlag'] == _filterTopic;
          }).toList();
        } else if (_filterTopic == 'Alle') {
          filteredDocs = allDocs;
        } else {
          filteredDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final raw = data['detectedTopic'] as String? ?? 'Allgemein';
            return _normalizeTopic(raw) == _filterTopic;
          }).toList();
        }

        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  _showFlaggedOnly
                      ? 'Keine auffälligen Gespräche'
                      : _filterTopic == 'Alle'
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

  Widget _buildGroupedList(
      List<QueryDocumentSnapshot> docs, String userId) {
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
                    '${entry.value.length} ${entry.value.length == 1 ? 'Gespräch' : 'Gespräche'}',
                    style:
                    TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            ...entry.value.map((doc) {
              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(
                      bottom: 12, left: 16, right: 16),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) => _confirmDelete(context),
                onDismissed: (_) => _deleteSession(
                    userId: userId, sessionId: doc.id),
                child: _SessionCard(
                  sessionId: doc.id,
                  data: doc.data() as Map<String, dynamic>,
                  child: widget.child,
                  userId: userId,
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  // ── Dialoge ───────────────────────────────────────────────────────────────

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            style:
            ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 8),
            Text('Alle löschen?'),
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
            style:
            ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
      builder: (_) =>
      const Center(child: CircularProgressIndicator()),
    );

    try {
      final tutorChatCleanupService = TutorChatCleanupService();
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
      final tutorChatCleanupService = TutorChatCleanupService();
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
      case 'physik':
        return 'Physik';
      case 'chemie':
        return 'Chemie';
      case 'biologie':
        return 'Biologie';
      case 'geschichte':
        return 'Geschichte';
      case 'geographie':
      case 'erdkunde':
        return 'Geographie';
      case 'informatik':
        return 'Informatik';
      case 'musik':
        return 'Musik';
      case 'latein':
        return 'Latein';
      case 'französisch':
        return 'Französisch';
      case 'spanisch':
        return 'Spanisch';
      default:
        return 'Allgemein';
    }
  }
}

// ============================================================================
// FLAG-FILTER CHIP
// ============================================================================

class _FlagFilterChip extends StatelessWidget {
  final String label;
  final String flagValue;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const _FlagFilterChip({
    required this.label,
    required this.flagValue,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withOpacity(isSelected ? 1.0 : 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
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
    final contentFlag = data['contentFlag'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      elevation: contentFlag != null ? 3 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Farbiger Rand bei flagged Sessions
        side: contentFlag == 'critical'
            ? const BorderSide(color: Colors.red, width: 1.5)
            : contentFlag == 'off_topic'
            ? BorderSide(color: Colors.orange.shade400, width: 1.5)
            : BorderSide.none,
      ),
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
              contentFlag: contentFlag,
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
                  // Fach-Icon
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

              // ── Content-Flag Banner ──────────────────────────────────────
              if (contentFlag != null) ...[
                const SizedBox(height: 10),
                _ContentFlagBanner(flag: contentFlag),
              ],

              // ── Erste Frage ──────────────────────────────────────────────
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
                    style:
                    TextStyle(fontSize: 11, color: Colors.grey[400]),
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
      case 'physik':
        return 'Physik';
      case 'chemie':
        return 'Chemie';
      case 'biologie':
        return 'Biologie';
      case 'geschichte':
        return 'Geschichte';
      case 'geographie':
      case 'erdkunde':
        return 'Geographie';
      default:
        return topic.isEmpty ? 'Allgemein' : topic;
    }
  }

  Color _topicColor(String topic) {
    switch (topic) {
      case 'Mathematik':
        return Colors.orange;
      case 'Deutsch':
        return Colors.red.shade700;
      case 'Englisch':
        return Colors.blue;
      case 'Sachkunde':
        return Colors.green;
      case 'Physik':
        return Colors.indigo;
      case 'Chemie':
        return Colors.teal;
      case 'Biologie':
        return Colors.lightGreen.shade700;
      case 'Geschichte':
        return Colors.brown;
      case 'Geographie':
        return Colors.cyan.shade700;
      case 'Informatik':
        return Colors.blueGrey;
      case 'Musik':
        return Colors.pink;
      case 'Latein':
        return Colors.deepOrange;
      case 'Französisch':
        return Colors.blue.shade800;
      case 'Spanisch':
        return Colors.red.shade800;
      default:
        return Colors.deepPurple;
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
        return Icons.nature;
      case 'Physik':
        return Icons.science;
      case 'Chemie':
        return Icons.biotech;
      case 'Biologie':
        return Icons.eco;
      case 'Geschichte':
        return Icons.history_edu;
      case 'Geographie':
        return Icons.public;
      case 'Informatik':
        return Icons.computer;
      case 'Musik':
        return Icons.music_note;
      case 'Latein':
        return Icons.translate;
      case 'Französisch':
        return Icons.translate;
      case 'Spanisch':
        return Icons.translate;
      default:
        return Icons.chat;
    }
  }
}

// ============================================================================
// CONTENT FLAG BANNER
// ============================================================================

class _ContentFlagBanner extends StatelessWidget {
  final String flag;

  const _ContentFlagBanner({required this.flag});

  @override
  Widget build(BuildContext context) {
    final isCritical = flag == 'critical';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isCritical ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCritical
              ? Colors.red.shade200
              : Colors.orange.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.warning_rounded : Icons.info_outline,
            size: 16,
            color: isCritical ? Colors.red.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isCritical
                  ? '🚨 Bedenklicher Inhalt – bitte Gespräch prüfen'
                  : '⚠️ Nicht-Schulthema – außerhalb des Lernbereichs',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isCritical
                    ? Colors.red.shade700
                    : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
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
  final String? contentFlag;

  const _SessionDetailScreen({
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
      body: Column(
        children: [
          // Flag-Banner oben im Detail, wenn vorhanden
          if (contentFlag != null)
            _ContentFlagBanner(flag: contentFlag!),

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
                    final msg =
                    docs[i].data() as Map<String, dynamic>;
                    final isUser = msg['isUser'] as bool? ?? false;
                    final text = msg['text'] as String? ?? '';
                    final timestamp =
                    (msg['timestamp'] as Timestamp?)?.toDate();

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
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromDetail(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            style:
            ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen',
                style: TextStyle(color: Colors.white)),
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

  Color _topicColor(String topic) {
    switch (topic) {
      case 'Mathematik':
        return Colors.orange;
      case 'Deutsch':
        return Colors.red.shade700;
      case 'Englisch':
        return Colors.blue;
      case 'Sachkunde':
        return Colors.green;
      case 'Physik':
        return Colors.indigo;
      case 'Chemie':
        return Colors.teal;
      case 'Biologie':
        return Colors.lightGreen.shade700;
      case 'Geschichte':
        return Colors.brown;
      case 'Geographie':
        return Colors.cyan.shade700;
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
                isUser ? childName : 'Lerndex',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isUser ? topicColor : Colors.deepPurple,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? topicColor.withOpacity(0.1) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: Border.all(
                  color: isUser
                      ? topicColor.withOpacity(0.2)
                      : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${timestamp!.hour.toString().padLeft(2, '0')}:${timestamp!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}