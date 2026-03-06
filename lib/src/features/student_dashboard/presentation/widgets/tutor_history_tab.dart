import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/tutor/presentation/tutor_provider.dart';
import 'package:lerndex/src/features/tutor/presentation/tutor_screen.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/child_model.dart';
import '../../../auth/presentation/active_child_provider.dart';
import 'session_detail_screen.dart';

// ============================================================================
// TAB 2: TUTOR-VERLAUF (Schüler-Sicht)
// Filtert leere Sessions (messageCount <= 1) und gelöschte (status == 'deleted')
// ============================================================================

class TutorHistoryTab extends ConsumerWidget {
  final ChildModel child;

  const TutorHistoryTab({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const Center(child: Text('Nicht angemeldet'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(child.id)
          .collection('tutor_sessions')
          .orderBy('startedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Leere Sessions (nur Begrüßung) UND gelöschte Sessions ausfiltern
        final visibleDocs = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final msgCount = data['messageCount'] as int? ?? 0;
          final status = data['status'] as String? ?? '';
          return msgCount > 1 && status != 'deleted';
        }).toList();

        if (visibleDocs.isEmpty) {
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
                  'Noch kein Verlauf',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Starte ein Gespräch mit dem Tutor!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: visibleDocs.length,
          itemBuilder: (context, index) {
            final doc = visibleDocs[index];
            final session = doc.data() as Map<String, dynamic>;
            final startedAt = (session['startedAt'] as Timestamp?)?.toDate();
            final topic = session['detectedTopic'] as String? ?? 'Allgemein';
            final msgCount = session['messageCount'] as int? ?? 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(
                      userId: user.uid,
                      childId: child.id,
                      sessionId: doc.id,
                      topic: topic,
                      startedAt: startedAt,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _topicColor(topic).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _topicIcon(topic),
                          color: _topicColor(topic),
                          size: 22,
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
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _topicColor(topic),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              startedAt != null
                                  ? _formatDate(startedAt)
                                  : 'Datum unbekannt',
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
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () async {
                              final activeChild = ref.read(activeChildProvider);
                              if (activeChild == null || !context.mounted)
                                return;

                              // Resume-ID ZUERST setzen, dann Provider invalidieren.
                              // Der neue TutorNotifier liest die ID synchron in
                              // _loadChatHistoryInBackground bevor der erste await.
                              ref
                                  .read(tutorResumeSessionIdProvider.notifier)
                                  .state = doc
                                  .id;
                              ref.invalidate(
                                tutorProviderFamily(activeChild.id),
                              );
                              // XP-Provider ebenfalls zurücksetzen damit _loadDailyXpAndHistory
                              // den korrekten Wert aus Firestore neu laden kann.
                              ref.invalidate(
                                tutorSessionXpProvider(activeChild.id),
                              );

                              if (context.mounted) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TutorScreen(),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 13,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Fortsetzen',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'Heute';
    if (dateOnly == yesterday) return 'Gestern';
    return '${date.day}.${date.month}.${date.year}';
  }

  Color _topicColor(String topic) {
    switch (topic) {
      case 'Mathematik':
      case 'Mathe':
        return Colors.orange;
      case 'Deutsch':
        return Colors.red;
      case 'Englisch':
        return Colors.blue;
      case 'Sachkunde':
      case 'Biologie':
        return Colors.green;
      case 'Physik':
        return Colors.indigo;
      case 'Geschichte':
        return Colors.brown;
      default:
        return Colors.deepPurple;
    }
  }

  IconData _topicIcon(String topic) {
    switch (topic) {
      case 'Mathematik':
      case 'Mathe':
        return Icons.calculate_rounded;
      case 'Deutsch':
        return Icons.menu_book_rounded;
      case 'Englisch':
        return Icons.language_rounded;
      case 'Sachkunde':
      case 'Biologie':
        return Icons.science_rounded;
      case 'Physik':
        return Icons.bolt_rounded;
      case 'Geschichte':
        return Icons.account_balance_rounded;
      default:
        return Icons.chat_rounded;
    }
  }
}
