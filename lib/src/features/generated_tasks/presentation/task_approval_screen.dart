import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/generated_task_models.dart';
import '../data/generated_task_repository.dart';
import '../../auth/data/auth_repository.dart';


/// 🔍 FREIGABE-SCREEN FÜR GENERIERTE AUFGABEN
///
/// Eltern können hier:
/// - Alle generierten Aufgaben-Batches sehen
/// - Details jedes Batches ansehen
/// - Einzelne Aufgaben freigeben oder ablehnen
/// - Alle Aufgaben eines Batches auf einmal freigeben
/// - Batches löschen

class TaskApprovalScreen extends ConsumerWidget {
  const TaskApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authRepo = ref.watch(authRepositoryProvider);
    final userId = authRepo.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Nicht angemeldet')),
      );
    }

    final batchesAsync = ref.watch(generatedBatchesProvider(userId));

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Aufgaben freigeben'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: batchesAsync.when(
        data: (batches) {
          if (batches.isEmpty) {
            return _buildEmptyState();
          }

          // Gruppiere nach Status
          final pending = batches.where((b) => b.pendingTasks > 0).toList();
          final reviewed = batches.where((b) => b.pendingTasks == 0).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ...[
                _buildSectionHeader(
                  title: 'Warten auf Freigabe',
                  count: pending.length,
                  color: Colors.orange,
                ),
                const SizedBox(height: 12),
                ...pending.map((batch) => _BatchCard(batch: batch)),
                const SizedBox(height: 24),
              ],
              if (reviewed.isNotEmpty) ...[
                _buildSectionHeader(
                  title: 'Bereits bearbeitet',
                  count: reviewed.length,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                ...reviewed.map((batch) => _BatchCard(batch: batch)),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Fehler: $error'),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Keine Aufgaben vorhanden',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Generiere KI-Aufgaben für deine Kinder',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 📦 BATCH CARD - Zeigt Übersicht eines Aufgaben-Batches
class _BatchCard extends ConsumerWidget {
  final GeneratedTaskBatch batch;

  const _BatchCard({required this.batch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasReviewed = batch.reviewProgress > 0;
    final isFullyReviewed = batch.isFullyReviewed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BatchDetailScreen(batch: batch),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  // Vorschaubild
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      batch.imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.image_not_supported),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.childName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              _getSubjectIcon(batch.subject),
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              batch.subject.displayName,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Status-Übersicht
              Row(
                children: [
                  _StatusChip(
                    icon: Icons.schedule,
                    label: 'Ausstehend',
                    count: batch.pendingTasks,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    icon: Icons.check_circle,
                    label: 'Freigegeben',
                    count: batch.approvedTasks,
                    color: Colors.green,
                  ),
                  if (batch.rejectedTasks > 0) ...[
                    const SizedBox(width: 8),
                    _StatusChip(
                      icon: Icons.cancel,
                      label: 'Abgelehnt',
                      count: batch.rejectedTasks,
                      color: Colors.red,
                    ),
                  ],
                ],
              ),

              // Fortschrittsbalken
              if (hasReviewed && !isFullyReviewed) ...[
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fortschritt: ${batch.reviewProgress.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: batch.reviewProgress / 100,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.deepPurple,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ],

              // Zeitstempel
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(batch.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        return Icons.science;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return 'vor ${difference.inMinutes} Min.';
      }
      return 'vor ${difference.inHours} Std.';
    } else if (difference.inDays == 1) {
      return 'Gestern';
    } else if (difference.inDays < 7) {
      return 'vor ${difference.inDays} Tagen';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}

/// 🏷️ STATUS CHIP
class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.batch.childName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (widget.batch.pendingTasks > 0)
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
                  _InfoRow(
                    icon: Icons.person,
                    label: 'Schüler',
                    value: widget.batch.childName,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: _getSubjectIcon(widget.batch.subject),
                    label: 'Fach',
                    value: widget.batch.subject.displayName,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
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
              'Aufgaben (${widget.batch.totalTasks})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            ...widget.batch.questions.asMap().entries.map((entry) {
              return _QuestionCard(
                question: entry.value,
                index: entry.key + 1,
                batchId: widget.batch.id,
                onStatusChanged: () => setState(() {}),
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
        return Icons.science;
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
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
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

      await repository.deleteBatch(
        userId: userId,
        batchId: widget.batch.id,
      );

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
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// 📝 QUESTION CARD - Einzelne Frage mit Freigabe-Buttons
class _QuestionCard extends ConsumerStatefulWidget {
  final GeneratedQuestion question;
  final int index;
  final String batchId;
  final VoidCallback onStatusChanged;

  const _QuestionCard({
    required this.question,
    required this.index,
    required this.batchId,
    required this.onStatusChanged,
  });

  @override
  ConsumerState<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<_QuestionCard> {
  bool _showSolution = false;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final statusIcon = _getStatusIcon();
    final statusText = widget.question.status.displayName;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${widget.index}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.question.topic,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // Frage
            Text(
              widget.question.question,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 16),

            // Antwortmöglichkeiten
            ...widget.question.options.asMap().entries.map((entry) {
              final isCorrect = entry.value == widget.question.correctAnswer;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCorrect ? Colors.green.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCorrect ? Colors.green.shade300 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    if (isCorrect)
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                    if (isCorrect) const SizedBox(width: 8),
                    Expanded(child: Text(entry.value)),
                  ],
                ),
              );
            }),

            // Lösung
            if (widget.question.solution != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _showSolution = !_showSolution),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: _showSolution ? Colors.blue.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showSolution ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: _showSolution ? Colors.blue.shade700 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showSolution ? 'Erklärung ausblenden' : 'Erklärung anzeigen',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _showSolution ? Colors.blue.shade700 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showSolution) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    widget.question.solution!,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ],

            // Action Buttons (nur bei pending)
            if (widget.question.status == TaskApprovalStatus.pending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Freigeben'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _reject,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.close, size: 20),
                      label: const Text('Ablehnen'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (widget.question.status) {
      case TaskApprovalStatus.pending:
        return Colors.orange;
      case TaskApprovalStatus.approved:
        return Colors.green;
      case TaskApprovalStatus.rejected:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.question.status) {
      case TaskApprovalStatus.pending:
        return Icons.schedule;
      case TaskApprovalStatus.approved:
        return Icons.check_circle;
      case TaskApprovalStatus.rejected:
        return Icons.cancel;
    }
  }

  Future<void> _approve() async {
    setState(() => _isProcessing = true);

    try {
      final repository = ref.read(generatedTaskRepositoryProvider);
      final authRepo = ref.read(authRepositoryProvider);
      final userId = authRepo.currentUser?.uid;

      if (userId == null) throw Exception('Nicht angemeldet');

      await repository.approveQuestion(
        userId: userId,
        batchId: widget.batchId,
        questionId: widget.question.id,
        approvedByUserId: userId,
      );

      widget.onStatusChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Aufgabe freigegeben'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _isProcessing = true);

    try {
      final repository = ref.read(generatedTaskRepositoryProvider);
      final authRepo = ref.read(authRepositoryProvider);
      final userId = authRepo.currentUser?.uid;

      if (userId == null) throw Exception('Nicht angemeldet');

      await repository.rejectQuestion(
        userId: userId,
        batchId: widget.batchId,
        questionId: widget.question.id,
      );

      widget.onStatusChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Aufgabe abgelehnt'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}