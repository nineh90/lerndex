import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../data/generated_task_repository.dart';
import 'widgets/batch_card.dart';

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
      return const Scaffold(body: Center(child: Text('Nicht angemeldet')));
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
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 12),
                ...pending.map((batch) => BatchCard(batch: batch)),
                const SizedBox(height: 24),
              ],
              if (reviewed.isNotEmpty) ...[
                _buildSectionHeader(
                  title: 'Bereits bearbeitet',
                  count: reviewed.length,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                ...reviewed.map((batch) => BatchCard(batch: batch)),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Fehler: $error')),
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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
