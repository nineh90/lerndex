import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/generated_task_models.dart';
import '../../data/generated_task_repository.dart';
import '../../../auth/data/auth_repository.dart';

/// 📝 QUESTION CARD - Einzelne Frage mit Freigabe-Buttons
class QuestionCard extends ConsumerStatefulWidget {
  final GeneratedQuestion question;
  final int index;
  final String batchId;
  final VoidCallback onStatusChanged;

  const QuestionCard({
    super.key,
    required this.question,
    required this.index,
    required this.batchId,
    required this.onStatusChanged,
  });

  @override
  ConsumerState<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<QuestionCard> {
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                    color: isCorrect
                        ? Colors.green.shade300
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    if (isCorrect)
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _showSolution
                        ? Colors.blue.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showSolution ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: _showSolution
                            ? Colors.blue.shade700
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showSolution
                            ? 'Erklärung ausblenden'
                            : 'Erklärung anzeigen',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _showSolution
                              ? Colors.blue.shade700
                              : Colors.grey.shade700,
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
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }
}
