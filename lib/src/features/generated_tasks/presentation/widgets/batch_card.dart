import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/generated_task_models.dart';
import '../batch_detail_screen.dart';
import 'status_chip.dart';

/// 📦 BATCH CARD - Kompakte Übersicht eines Aufgaben-Batches
class BatchCard extends ConsumerWidget {
  final GeneratedTaskBatch batch;

  const BatchCard({super.key, required this.batch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFullyReviewed = batch.isFullyReviewed;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BatchDetailScreen(batch: batch)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Vorschaubild – kleiner
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildThumbnail(48),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${batch.childName} · ${batch.subject.displayName}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatDate(batch.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (batch.pendingTasks > 0)
                          _MiniChip(
                            label: '${batch.pendingTasks} offen',
                            color: Colors.deepPurple,
                          ),
                        if (batch.pendingTasks > 0 && batch.approvedTasks > 0)
                          const SizedBox(width: 6),
                        if (batch.approvedTasks > 0)
                          _MiniChip(
                            label: '${batch.approvedTasks} ✓',
                            color: Colors.green,
                          ),
                        if (batch.rejectedTasks > 0) ...[
                          const SizedBox(width: 6),
                          _MiniChip(
                            label: '${batch.rejectedTasks} ✗',
                            color: Colors.red,
                          ),
                        ],
                        const Spacer(),
                        if (isFullyReviewed)
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green.shade400,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(double size) {
    final url = batch.imageUrl;
    final hasValidUrl =
        url.isNotEmpty &&
        Uri.tryParse(url)?.hasAbsolutePath == true &&
        url.startsWith('http');

    if (!hasValidUrl) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getSubjectIcon(batch.subject),
          size: size * 0.45,
          color: Colors.grey.shade400,
        ),
      );
    }

    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getSubjectIcon(batch.subject),
          size: size * 0.45,
          color: Colors.grey.shade400,
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

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
