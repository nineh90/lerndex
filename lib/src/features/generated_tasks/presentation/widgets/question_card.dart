import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/generated_task_models.dart';
import '../../data/generated_task_repository.dart';
import '../../../auth/data/auth_repository.dart';

/// Aufklappbare Multiple-Choice-Karte mit zwei Modi:
///
/// Vorschau-Modus (task_generator_screen nach Generierung):
///   QuestionCard(question: q, index: 1)
///
/// Freigabe-Modus (batch_detail_screen mit Approve/Reject-Buttons):
///   QuestionCard(question: q, index: 1, batchId: '...', onStatusChanged: () {})
class QuestionCard extends ConsumerStatefulWidget {
  final GeneratedQuestion question;
  final int index;

  /// Nur im Freigabe-Modus nötig
  final String? batchId;
  final VoidCallback? onStatusChanged;

  const QuestionCard({
    super.key,
    required this.question,
    required this.index,
    this.batchId,
    this.onStatusChanged,
  });

  bool get _isApprovalMode => batchId != null && onStatusChanged != null;

  @override
  ConsumerState<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<QuestionCard> {
  bool _expanded = false;
  bool _showSolution = false;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget._isApprovalMode
        ? _getStatusColor().withValues(alpha: 0.3)
        : _getDifficultyColor().withValues(alpha: 0.3);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: InkWell(
        onTap: widget._isApprovalMode
            ? null
            : () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              _buildQuestion(),
              if (widget._isApprovalMode) ...[
                _buildApprovalContent(),
              ] else ...[
                _buildPreviewContent(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    if (widget._isApprovalMode) {
      // Freigabe-Modus: Status-Anzeige
      final statusColor = _getStatusColor();
      final statusIcon = _getStatusIcon();
      return Row(
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
                  fontSize: 16,
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
                  widget.question.topic,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      widget.question.status.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Vorschau-Modus: Schwierigkeits-Anzeige
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _getDifficultyColor(),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${widget.index}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
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
                widget.question.topic,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  Icon(
                    _getDifficultyIcon(),
                    size: 16,
                    color: _getDifficultyColor(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getDifficultyText(),
                    style: TextStyle(
                      fontSize: 11,
                      color: _getDifficultyColor(),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Icon(
          _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: Colors.grey,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FRAGE
  // ---------------------------------------------------------------------------

  Widget _buildQuestion() {
    return Text(
      widget.question.question,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VORSCHAU-MODUS (aufklappbar, kein Approve/Reject)
  // ---------------------------------------------------------------------------

  Widget _buildPreviewContent() {
    if (!_expanded) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Tippen zum Aufklappen · ${widget.question.options.length} Antwortmöglichkeiten',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        ...widget.question.options.map((option) {
          final isCorrect = option == widget.question.correctAnswer;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCorrect ? Colors.green.shade300 : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCorrect ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: isCorrect ? Colors.green : Colors.grey.shade400,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 14,
                      color: isCorrect
                          ? Colors.green.shade800
                          : Colors.grey.shade700,
                      fontWeight: isCorrect
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (widget.question.solution != null &&
            widget.question.solution!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Erklärung',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.question.solution!,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FREIGABE-MODUS (mit Approve/Reject-Buttons + Lösung)
  // ---------------------------------------------------------------------------

  Widget _buildApprovalContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Antwortmöglichkeiten
        ...widget.question.options.map((option) {
          final isCorrect = option == widget.question.correctAnswer;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCorrect ? Colors.green.shade300 : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCorrect ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: isCorrect ? Colors.green : Colors.grey.shade400,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 14,
                      color: isCorrect
                          ? Colors.green.shade800
                          : Colors.grey.shade700,
                      fontWeight: isCorrect
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        // Lösung ein-/ausklappen
        if (widget.question.solution != null &&
            widget.question.solution!.isNotEmpty) ...[
          TextButton.icon(
            onPressed: () => setState(() => _showSolution = !_showSolution),
            icon: Icon(_showSolution ? Icons.visibility_off : Icons.visibility),
            label: Text(
              _showSolution ? 'Lösung ausblenden' : 'Lösung anzeigen',
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.deepPurple,
              padding: EdgeInsets.zero,
            ),
          ),
          if (_showSolution)
            Container(
              width: double.infinity,
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

        // Approve / Reject (nur wenn noch pending)
        if (widget.question.status == TaskApprovalStatus.pending) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _reject,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Ablehnen'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _approve,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Freigeben'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // AKTIONEN
  // ---------------------------------------------------------------------------

  Future<void> _approve() async {
    setState(() => _isProcessing = true);
    try {
      final userId = ref.read(authRepositoryProvider).currentUser?.uid;
      if (userId == null) return;
      await ref
          .read(generatedTaskRepositoryProvider)
          .approveQuestion(
            userId: userId,
            batchId: widget.batchId!,
            questionId: widget.question.id,
            approvedByUserId: userId,
          );
      widget.onStatusChanged?.call();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _isProcessing = true);
    try {
      final userId = ref.read(authRepositoryProvider).currentUser?.uid;
      if (userId == null) return;
      await ref
          .read(generatedTaskRepositoryProvider)
          .rejectQuestion(
            userId: userId,
            batchId: widget.batchId!,
            questionId: widget.question.id,
          );
      widget.onStatusChanged?.call();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // HILFSMETHODEN
  // ---------------------------------------------------------------------------

  Color _getDifficultyColor() {
    switch (widget.question.difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'hard':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getDifficultyIcon() {
    switch (widget.question.difficulty.toLowerCase()) {
      case 'easy':
        return Icons.trending_down;
      case 'hard':
        return Icons.trending_up;
      default:
        return Icons.trending_flat;
    }
  }

  String _getDifficultyText() {
    switch (widget.question.difficulty.toLowerCase()) {
      case 'easy':
        return 'Leicht';
      case 'hard':
        return 'Schwer';
      default:
        return 'Mittel';
    }
  }

  Color _getStatusColor() {
    switch (widget.question.status) {
      case TaskApprovalStatus.approved:
        return Colors.green;
      case TaskApprovalStatus.rejected:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.question.status) {
      case TaskApprovalStatus.approved:
        return Icons.check_circle;
      case TaskApprovalStatus.rejected:
        return Icons.cancel;
      default:
        return Icons.pending;
    }
  }
}
