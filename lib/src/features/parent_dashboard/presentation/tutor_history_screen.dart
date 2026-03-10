import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../../services/tutor_chat_cleanup_service.dart';
import 'widgets/flag_filter_chip.dart';
import 'widgets/session_card.dart';

/// 💬 CHAT-HISTORIE FÜR ELTERN
/// - Dynamische Topic-Filter (nur tatsächlich vorhandene Topics)
/// - ⚠️ / 🚨 Content-Flag-Badges für auffällige Gespräche
/// - Filterchip "⚠️ Auffällig" für schnellen Überblick
/// - Leere Sessions ausgeblendet (messageCount <= 1)
/// - Swipe-to-delete + Bestätigungs-Dialog
class TutorHistoryScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const TutorHistoryScreen({super.key, required this.child});

  @override
  ConsumerState<TutorHistoryScreen> createState() => _TutorHistoryScreenState();
}

class _TutorHistoryScreenState extends ConsumerState<TutorHistoryScreen> {
  String _filterTopic = 'Alle';
  List<String> _availableTopics = ['Alle'];

  // Sonderfilter: zeigt nur Sessions mit contentFlag
  bool _showFlaggedOnly = false;

  // Lokal gelöschte Session-IDs – sofortiges Ausblenden vor Stream-Update
  // verhindert den "Dismissible still in tree"-Fehler
  final Set<String> _deletedIds = {};

  // Heute verdiente Tutor-XP – direkt aus dem Child-Dokument geladen
  int _todayXp = 0;

  @override
  void initState() {
    super.initState();
    _loadTodayXp();
  }

  Future<void> _loadTodayXp() async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(widget.child.id)
          .get();
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      final lastDate = (data['tutorXpLastDate'] as Timestamp?)?.toDate();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (lastDate != null &&
          DateTime(lastDate.year, lastDate.month, lastDate.day) == today) {
        if (mounted) {
          setState(() => _todayXp = (data['tutorXpToday'] as int?) ?? 0);
        }
      }
    } catch (_) {
      // Fehler beim Laden – Badge bleibt leer
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Nicht angemeldet')));
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                children: _availableTopics.map((topic) {
                  final selected = topic == _filterTopic && !_showFlaggedOnly;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(topic),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _filterTopic = topic;
                        _showFlaggedOnly = false;
                      }),
                      backgroundColor: Colors.white,
                      selectedColor: Colors.deepPurple,
                      checkmarkColor: Colors.white,
                      showCheckmark: true,
                      side: BorderSide(
                        color: selected
                            ? Colors.deepPurple
                            : Colors.deepPurple.shade200,
                      ),
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
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 8,
                top: 2,
              ),
              child: Row(
                children: [
                  // ⚠️ Chip
                  FlagFilterChip(
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
                  FlagFilterChip(
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

        // Leere Sessions ausblenden + lokal gelöschte sofort ausfiltern
        final allDocs = (snapshot.data?.docs ?? []).where((doc) {
          if (_deletedIds.contains(doc.id)) return false;
          final data = doc.data() as Map<String, dynamic>;
          final msgCount = (data['messageCount'] as int? ?? 0);
          final hasFlag = data['contentFlag'] != null;
          return msgCount > 1 || hasFlag;
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
                if (!sortedTopics.contains(_filterTopic) && !_showFlaggedOnly) {
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
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.grey[300],
                ),
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
        // Tutor-XP für diesen Tag ermitteln:
        // → Heute: direkt aus tutorXpToday im Child-Dokument (zuverlässig,
        //          unabhängig davon ob xpEarned in den Sessions gesetzt ist)
        // → Vergangene Tage: xpEarned aus den Sessions summieren
        final isToday = entry.key == 'Heute';
        final dailyXp = isToday
            ? _todayXp
            : entry.value.fold<int>(0, (sum, doc) {
                final data = doc.data() as Map<String, dynamic>;
                return sum + ((data['xpEarned'] as int?) ?? 0);
              });
        const kMaxXpPerDay = 50;
        final xpCapped = dailyXp.clamp(0, kMaxXpPerDay);

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
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const Spacer(),
                  // ⚡ Tutor-XP Badge für diesen Tag
                  if (dailyXp > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: xpCapped >= kMaxXpPerDay
                            ? Colors.orange.shade100
                            : Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: xpCapped >= kMaxXpPerDay
                              ? Colors.orange.shade400
                              : Colors.deepPurple.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            xpCapped >= kMaxXpPerDay ? '🏆' : '⚡',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$xpCapped / $kMaxXpPerDay XP',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: xpCapped >= kMaxXpPerDay
                                  ? Colors.orange.shade800
                                  : Colors.deepPurple.shade700,
                            ),
                          ),
                        ],
                      ),
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
                    bottom: 12,
                    left: 16,
                    right: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) => _confirmDelete(context),
                onDismissed: (_) {
                  setState(() => _deletedIds.add(doc.id));
                  _deleteSession(userId: userId, sessionId: doc.id);
                },
                child: SessionCard(
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Alle löschen',
              style: TextStyle(color: Colors.white),
            ),
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
      final tutorChatCleanupService = TutorChatCleanupService();
      await tutorChatCleanupService.deleteAllSessionsForChild(
        userId: userId,
        childId: widget.child.id,
      );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler beim Löschen: $e')));
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

    final weekday = [
      'Mo',
      'Di',
      'Mi',
      'Do',
      'Fr',
      'Sa',
      'So',
    ][date.weekday - 1];
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
