import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../data/generated_task_repository.dart';
import '../data/generated_task_models.dart';
import 'widgets/batch_card.dart';
import 'batch_detail_screen.dart';

/// 🔍 FREIGABE-SCREEN FÜR GENERIERTE AUFGABEN
///
/// - Ausstehende Batches oben, prominent
/// - Bereits vollständig bearbeitete Batches in ausgeklappter Sektion ganz unten
/// - Kompakte, übersichtliche Kacheln
class TaskApprovalScreen extends ConsumerStatefulWidget {
  final String childId;

  /// Wenn gesetzt, wird dieser Batch direkt beim Start geöffnet
  final String? initialBatchId;

  const TaskApprovalScreen({
    super.key,
    required this.childId,
    this.initialBatchId,
  });

  @override
  ConsumerState<TaskApprovalScreen> createState() => _TaskApprovalScreenState();
}

class _TaskApprovalScreenState extends ConsumerState<TaskApprovalScreen> {
  bool _reviewedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final authRepo = ref.watch(authRepositoryProvider);
    final userId = authRepo.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Nicht angemeldet')));
    }

    final batchesAsync = ref.watch(
      generatedBatchesForChildProvider((
        userId: userId,
        childId: widget.childId,
      )),
    );

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Aufgaben freigeben'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: batchesAsync.when(
        data: (batches) {
          if (batches.isEmpty) return _buildEmptyState();

          final pending = batches.where((b) => b.pendingTasks > 0).toList();
          final reviewed = batches.where((b) => b.pendingTasks == 0).toList();

          // Falls ein initialer Batch angegeben wurde, direkt öffnen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _openInitialBatchIfNeeded(context, batches);
          });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              // ---- AUSSTEHEND ----
              if (pending.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Warten auf Freigabe',
                  count: pending.length,
                  color: Colors.deepPurple,
                  icon: Icons.pending_actions,
                ),
                const SizedBox(height: 8),
                ...pending.map((batch) => BatchCard(batch: batch)),
                const SizedBox(height: 20),
              ],

              // ---- BEREITS BEARBEITET (eingeklappt) ----
              if (reviewed.isNotEmpty) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () =>
                      setState(() => _reviewedExpanded = !_reviewedExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Bereits bearbeitet (${reviewed.length})',
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
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_reviewedExpanded) ...[
                  const SizedBox(height: 8),
                  ...reviewed.map((batch) => BatchCard(batch: batch)),
                ],
              ],

              // Empty pending but has reviewed
              if (pending.isEmpty && reviewed.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _buildAllDoneHint(),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
      ),
    );
  }

  bool _initialBatchOpened = false;

  void _openInitialBatchIfNeeded(
    BuildContext context,
    List<GeneratedTaskBatch> batches,
  ) {
    if (_initialBatchOpened || widget.initialBatchId == null) return;
    final target = batches
        .where((b) => b.id == widget.initialBatchId)
        .firstOrNull;
    if (target == null) return;
    _initialBatchOpened = true;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BatchDetailScreen(batch: target)),
    );
  }

  Widget _buildAllDoneHint() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.celebration, color: Colors.green.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Alle Aufgaben wurden bearbeitet!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade800,
              ),
            ),
          ),
        ],
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
            size: 72,
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
            'Generiere KI-Aufgaben im Aufgaben-Generator.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
