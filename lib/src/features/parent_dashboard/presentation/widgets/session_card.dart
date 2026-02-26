import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/domain/child_model.dart';
import 'content_flag_banner.dart';
import 'session_detail_screen.dart';

// ============================================================================
// SESSION-KARTE
// ============================================================================

class SessionCard extends StatelessWidget {
  final String sessionId;
  final Map<String, dynamic> data;
  final ChildModel child;
  final String userId;

  const SessionCard({
    super.key,
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
            builder: (_) => SessionDetailScreen(
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
                            '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')} Uhr',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$msgCount Nachrichten',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
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
                ContentFlagBanner(flag: contentFlag),
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
                            fontSize: 13,
                            color: Colors.grey[800],
                          ),
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
