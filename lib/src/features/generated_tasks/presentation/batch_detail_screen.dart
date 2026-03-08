import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/generated_task_models.dart';
import '../data/generated_task_repository.dart';
import '../../auth/data/auth_repository.dart';
import 'widgets/info_row.dart';
import 'widgets/question_card.dart';

/// 📋 BATCH DETAIL SCREEN - Zeigt alle Aufgaben eines Batches
///
/// - Ausstehende Aufgaben oben
/// - Bereits freigegebene/abgelehnte ganz unten, eingeklappt
class BatchDetailScreen extends ConsumerStatefulWidget {
  final GeneratedTaskBatch batch;

  const BatchDetailScreen({super.key, required this.batch});

  @override
  ConsumerState<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends ConsumerState<BatchDetailScreen> {
  bool _isProcessing = false;
  bool _reviewedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final authRepo = ref.watch(authRepositoryProvider);
    final userId = authRepo.currentUser?.uid;

    final questionsAsync = userId != null
        ? ref.watch(
            batchQuestionsProvider((userId: userId, batchId: widget.batch.id)),
          )
        : null;

    final questions = questionsAsync?.value ?? widget.batch.questions;

    final pendingQuestions = questions
        .where((q) => q.status == TaskApprovalStatus.pending)
        .toList();
    final reviewedQuestions = questions
        .where((q) => q.status != TaskApprovalStatus.pending)
        .toList();

    final hasPending = pendingQuestions.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          '${widget.batch.childName} · ${widget.batch.subject.displayName}',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (hasPending)
            TextButton.icon(
              onPressed: _isProcessing ? null : _approveAll,
              icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
              label: const Text(
                'Alle freigeben',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'delete') _confirmDelete();
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
      body: CustomScrollView(
        slivers: [
          // --- Kompakte Header-Info ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildCompactHeader(),
            ),
          ),

          // --- Ausstehende Aufgaben ---
          if (pendingQuestions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pending_actions,
                      size: 16,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ausstehend (${pendingQuestions.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => QuestionCard(
                    question: pendingQuestions[index],
                    index: index + 1,
                    batchId: widget.batch.id,
                    onStatusChanged: () {},
                  ),
                  childCount: pendingQuestions.length,
                ),
              ),
            ),
          ],

          // --- Bereits bearbeitet (eingeklappt) ---
          if (reviewedQuestions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      setState(() => _reviewedExpanded = !_reviewedExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Bereits bearbeitet (${reviewedQuestions.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _reviewedExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.grey.shade500,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_reviewedExpanded)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => QuestionCard(
                      question: reviewedQuestions[index],
                      index: pendingQuestions.length + index + 1,
                      batchId: widget.batch.id,
                      onStatusChanged: () {},
                    ),
                    childCount: reviewedQuestions.length,
                  ),
                ),
              ),
          ],

          // --- Alle fertig ---
          if (!hasPending && reviewedQuestions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.celebration,
                        color: Colors.green.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Alle Aufgaben bearbeitet!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 56)),
        ],
      ),
    );
  }

  // Kompakter Header statt großem Bild + Info-Card
  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Kleines Vorschaubild
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              widget.batch.imageUrl,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: Colors.grey.shade100,
                child: Icon(
                  _getSubjectIcon(widget.batch.subject),
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.batch.childName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.batch.subject.displayName} · ${_formatDate(widget.batch.createdAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
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
    return '${date.day}.${date.month}.${date.year} · ${date.hour}:${date.minute.toString().padLeft(2, '0')} Uhr';
  }

  Future<void> _approveAll() async {
    setState(() => _isProcessing = true);
    try {
      final repository = ref.read(generatedTaskRepositoryProvider);
      final userId = ref.read(authRepositoryProvider).currentUser?.uid;
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
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batch löschen?'),
        content: const Text(
          'Möchtest du diesen Batch wirklich löschen? Alle Aufgaben werden entfernt.',
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
    if (confirmed == true) _deleteBatch();
  }

  Future<void> _deleteBatch() async {
    setState(() => _isProcessing = true);
    try {
      final repository = ref.read(generatedTaskRepositoryProvider);
      final userId = ref.read(authRepositoryProvider).currentUser?.uid;
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
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
