import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/generated_task_models.dart';
import '../data/generated_task_repository.dart';
import '../../auth/data/auth_repository.dart';
import 'widgets/info_row.dart';
import 'widgets/question_card.dart';

/// 📋 BATCH DETAIL SCREEN - Zeigt alle Aufgaben eines Batches
class BatchDetailScreen extends ConsumerStatefulWidget {
  final GeneratedTaskBatch batch;

  const BatchDetailScreen({super.key, required this.batch});

  @override
  ConsumerState<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends ConsumerState<BatchDetailScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final authRepo = ref.watch(authRepositoryProvider);
    final userId = authRepo.currentUser?.uid;

    // Live-Fragen per Stream – aktualisieren sich sofort nach approve/reject
    final questionsAsync = userId != null
        ? ref.watch(
            batchQuestionsProvider((userId: userId, batchId: widget.batch.id)),
          )
        : null;

    final questions = questionsAsync?.value ?? widget.batch.questions;
    final hasPending = questions.any(
      (q) => q.status == TaskApprovalStatus.pending,
    );

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.batch.childName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (hasPending)
            TextButton.icon(
              onPressed: _isProcessing ? null : _approveAll,
              icon: const Icon(Icons.done_all, color: Colors.white),
              label: const Text(
                'Alle freigeben',
                style: TextStyle(color: Colors.white),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Batch löschen'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bild-Vorschau
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                widget.batch.imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 24),

            // Info-Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  InfoRow(
                    icon: Icons.person,
                    label: 'Schüler',
                    value: widget.batch.childName,
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    icon: _getSubjectIcon(widget.batch.subject),
                    label: 'Fach',
                    value: widget.batch.subject.displayName,
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    icon: Icons.calendar_today,
                    label: 'Erstellt',
                    value: _formatDate(widget.batch.createdAt),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Aufgaben-Liste
            Text(
              'Aufgaben (${questions.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            ...questions.asMap().entries.map((entry) {
              return QuestionCard(
                question: entry.value,
                index: entry.key + 1,
                batchId: widget.batch.id,
                onStatusChanged:
                    () {}, // Kein setState nötig – Stream updated automatisch
              );
            }),
          ],
        ),
      ),
    );
  }

  IconData _getSubjectIcon(Subject subject) {
    switch (subject) {
      case Subject.mathe:
        return Icons.calculate;
      case Subject.deutsch:
        return Icons.menu_book;
      case Subject.englisch:
        return Icons.language;
      case Subject.sachkunde:
        return Icons.park;
      case Subject.biologie:
        return Icons.biotech;
      case Subject.chemie:
        return Icons.science;
      case Subject.physik:
        return Icons.bolt;
      case Subject.geschichte:
        return Icons.history_edu;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year} um ${date.hour}:${date.minute.toString().padLeft(2, '0')} Uhr';
  }

  Future<void> _approveAll() async {
    setState(() => _isProcessing = true);

    try {
      final repository = ref.read(generatedTaskRepositoryProvider);
      final authRepo = ref.read(authRepositoryProvider);
      final userId = authRepo.currentUser?.uid;

      if (userId == null) throw Exception('Nicht angemeldet');

      await repository.approveAllPendingInBatch(
        userId: userId,
        batchId: widget.batch.id,
        approvedByUserId: userId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Alle Aufgaben freigegeben!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batch löschen?'),
        content: const Text(
          'Möchtest du diesen Batch wirklich löschen? '
          'Alle Aufgaben werden entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteBatch();
    }
  }

  Future<void> _deleteBatch() async {
    setState(() => _isProcessing = true);

    try {
      final repository = ref.read(generatedTaskRepositoryProvider);
      final authRepo = ref.read(authRepositoryProvider);
      final userId = authRepo.currentUser?.uid;

      if (userId == null) throw Exception('Nicht angemeldet');

      await repository.deleteBatch(userId: userId, batchId: widget.batch.id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Batch gelöscht'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}
