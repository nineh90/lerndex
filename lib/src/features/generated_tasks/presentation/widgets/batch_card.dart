import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/generated_task_models.dart';
import '../batch_detail_screen.dart';
import 'status_chip.dart';

/// 📦 BATCH CARD - Zeigt Übersicht eines Aufgaben-Batches
class BatchCard extends ConsumerWidget {
  final GeneratedTaskBatch batch;

  const BatchCard({super.key, required this.batch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasReviewed = batch.reviewProgress > 0;
    final isFullyReviewed = batch.isFullyReviewed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BatchDetailScreen(batch: batch)),
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
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Status-Übersicht
              Row(
                children: [
                  StatusChip(
                    icon: Icons.schedule,
                    label: 'Ausstehend',
                    count: batch.pendingTasks,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    icon: Icons.check_circle,
                    label: 'Freigegeben',
                    count: batch.approvedTasks,
                    color: Colors.green,
                  ),
                  if (batch.rejectedTasks > 0) ...[
                    const SizedBox(width: 8),
                    StatusChip(
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
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(batch.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
