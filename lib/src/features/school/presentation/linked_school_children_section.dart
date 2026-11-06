import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../parent_dashboard/presentation/child_statistics_screen.dart';
import '../../parent_dashboard/presentation/tutor_history_screen.dart';
import '../../rewards/presentation/manage_rewards_screen.dart';
import '../data/parent_link_repository.dart';
import '../domain/class_stats.dart';
import '../../../shared/user_message.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';

/// Eltern-Dashboard: Kinder, die über den Elternbrief der Schule verbunden
/// sind. Statistik, Belohnungen und Lexi-Gespräche wie bei eigenen Kindern;
/// gelernt wird mit der Heimkarte aus dem Elternbrief.
class LinkedSchoolChildrenSection extends ConsumerWidget {
  const LinkedSchoolChildrenSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(schoolChildLinksProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (links.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              'Kinder in der Schule',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.purple,
              ),
            ),
          ),
          for (final link in links) _LinkedChildCard(link: link),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => connectSchoolChild(context, ref),
            icon: const Icon(Icons.school_outlined),
            label: const Text('Kind aus der Schule verbinden'),
          ),
        ),
      ],
    );
  }
}

/// Code aus dem Elternbrief eingeben und verbinden.
Future<void> connectSchoolChild(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Kind aus der Schule verbinden'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Den Code findest du im Elternbrief der Schule (oder einfach den '
            'QR-Code „Eltern verbinden“ mit der Kamera scannen). Für '
            'Schulkinder brauchst du kein Abo.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: 'K7MX-Q2PA',
              counterText: '',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Verbinden'),
        ),
      ],
    ),
  );
  if (code == null || code.isEmpty || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final name = await ref.read(parentLinkRepositoryProvider).link(code);
    messenger.showSnackBar(
      SnackBar(content: Text('$name ist jetzt verbunden.')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(userMessage(e)), backgroundColor: Colors.red),
    );
  }
}

class _LinkedChildCard extends ConsumerWidget {
  const _LinkedChildCard({required this.link});

  final SchoolChildLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(linkedSchoolChildProvider(link)).value;
    final place = [
      link.schoolName,
      if (link.className.isNotEmpty) 'Klasse ${link.className}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.purple.shade50,
                  child: const Icon(Icons.school, color: AppColors.purple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child?.name ?? link.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        place,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (_) => _unlink(context, ref),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'unlink',
                      child: Text('Verbindung trennen'),
                    ),
                  ],
                ),
              ],
            ),
            if (child == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Lädt …'),
              )
            else ...[
              const SizedBox(height: 8),
              Text(
                'Level ${child.level} · ${durationLabel(child.totalLearningSeconds)} '
                'gelernt · zuletzt ${lastActiveLabel(lastActivity(child), DateTime.now())}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _push(
                      context,
                      ChildStatisticsScreen(
                        child: child,
                        ownerUid: link.ownerUid,
                      ),
                    ),
                    icon: const Icon(Icons.bar_chart, size: 18),
                    label: const Text('Statistik'),
                  ),
                  TextButton.icon(
                    onPressed: () => _push(
                      context,
                      ManageRewardsScreen(
                        child: child,
                        ownerUid: link.ownerUid,
                      ),
                    ),
                    icon: const Icon(Icons.card_giftcard, size: 18),
                    label: const Text('Belohnungen'),
                  ),
                  TextButton.icon(
                    onPressed: () => _push(
                      context,
                      TutorHistoryScreen(child: child, ownerUid: link.ownerUid),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Lexi-Gespräche'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _unlink(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verbindung trennen?'),
        content: Text(
          '${link.name} verschwindet aus deinem Elternbereich. In der Schule '
          'bleibt alles, wie es ist. Mit dem Elternbrief kannst du dich '
          'jederzeit wieder verbinden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trennen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(parentLinkRepositoryProvider).unlink(link);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(e))));
      }
    }
  }
}
