import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/reward_model.dart';
import '../data/reward_repository.dart';
import '../../auth/domain/child_model.dart';

/// Screen für Eltern: Belohnungen verwalten
class ManageRewardsScreen extends ConsumerWidget {
  final ChildModel child;

  const ManageRewardsScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewardsAsync = ref.watch(childRewardsProvider(child.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Belohnungen für ${child.name}'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: rewardsAsync.when(
        data: (rewards) {
          if (rewards.isEmpty) {
            return _buildEmptyState(context, ref);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rewards.length,
            itemBuilder: (context, index) {
              final reward = rewards[index];
              return _RewardManageCard(
                reward: reward,
                childId: child.id,
                onEdit: () => _showEditDialog(context, ref, reward),
                onDelete: () => _deleteReward(context, ref, reward),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Fehler: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        label: const Text('Belohnung hinzufügen'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.card_giftcard, size: 100, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            'Noch keine Belohnungen',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Erstelle Belohnungen für dein Kind!',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => _showAddDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Belohnung hinzufügen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => _showSuggestionsDialog(context, ref),
            child: const Text('💡 Vorschläge anzeigen'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedIcon = '🎁';
    String selectedTrigger = RewardTrigger.level;
    int triggerValue = 5;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Neue Belohnung'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon-Auswahl
                Row(
                  children: [
                    const Text('Icon: '),
                    const SizedBox(width: 12),
                    ...['🎁', '💰', '🎬', '🍕', '🎮', '🏠', '🎢', '🌙'].map((icon) {
                      return GestureDetector(
                        onTap: () => setState(() => selectedIcon = icon),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selectedIcon == icon
                                ? Colors.deepPurple.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedIcon == icon
                                  ? Colors.deepPurple
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Text(icon, style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 16),

                // Titel
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titel',
                    hintText: 'z.B. 10€ Taschengeld',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Beschreibung
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung',
                    hintText: 'z.B. Extra Taschengeld für fleißiges Lernen',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Trigger-Typ
                DropdownButtonFormField<String>(
                  value: selectedTrigger,
                  decoration: const InputDecoration(
                    labelText: 'Auslöser',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: RewardTrigger.level,
                      child: Text(RewardTrigger.getDisplayName(RewardTrigger.level)),
                    ),
                    DropdownMenuItem(
                      value: RewardTrigger.stars,
                      child: Text(RewardTrigger.getDisplayName(RewardTrigger.stars)),
                    ),
                    DropdownMenuItem(
                      value: RewardTrigger.learningTime,
                      child: Text(RewardTrigger.getDisplayName(RewardTrigger.learningTime)),
                    ),
                  ],
                  onChanged: (value) => setState(() => selectedTrigger = value!),
                ),
                const SizedBox(height: 16),

                // Trigger-Wert
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Wert',
                    hintText: _getTriggerHint(selectedTrigger),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => triggerValue = int.tryParse(value) ?? 5,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showSuggestionsDialog(context, ref);
              },
              child: const Text('💡 Vorschläge'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  ref.read(rewardRepositoryProvider).addReward(
                    childId: child.id,
                    title: titleController.text,
                    description: descriptionController.text,
                    icon: selectedIcon,
                    trigger: selectedTrigger,
                    triggerValue: triggerValue,
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuggestionsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('💡 Belohnungs-Vorschläge'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: DefaultRewards.suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = DefaultRewards.suggestions[index];
              return Card(
                child: ListTile(
                  leading: Text(
                    suggestion['icon'],
                    style: const TextStyle(fontSize: 32),
                  ),
                  title: Text(suggestion['title']),
                  subtitle: Text(suggestion['description']),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () {
                      ref.read(rewardRepositoryProvider).addReward(
                        childId: child.id,
                        title: suggestion['title'],
                        description: suggestion['description'],
                        icon: suggestion['icon'],
                        trigger: suggestion['trigger'],
                        triggerValue: suggestion['triggerValue'],
                      );
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Reward reward) {
    // Ähnlich wie _showAddDialog, aber mit vorausgefüllten Werten
    // Vereinfacht für Kürze
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bearbeiten kommt bald!')),
    );
  }

  void _deleteReward(BuildContext context, WidgetRef ref, Reward reward) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Belohnung löschen?'),
        content: Text('Möchtest du "${reward.title}" wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(rewardRepositoryProvider).deleteReward(child.id, reward.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  String _getTriggerHint(String trigger) {
    switch (trigger) {
      case RewardTrigger.level:
        return 'z.B. 5 für Level 5';
      case RewardTrigger.stars:
        return 'z.B. 100 für 100 Sterne';
      case RewardTrigger.learningTime:
        return 'z.B. 60 für 60 Minuten';
      default:
        return '';
    }
  }
}

class _RewardManageCard extends StatelessWidget {
  final Reward reward;
  final String childId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RewardManageCard({
    required this.reward,
    required this.childId,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: _getStatusColor().withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(reward.icon, style: const TextStyle(fontSize: 28)),
          ),
        ),
        title: Text(reward.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reward.description),
            const SizedBox(height: 4),
            Text(
              RewardTrigger.getDescription(reward.trigger, reward.triggerValue),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            _buildStatusChip(),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Bearbeiten'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Löschen', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    String text;
    if (reward.isRedeemed) {
      text = '✅ Eingelöst';
    } else if (reward.isUnlocked) {
      text = '🎁 Verfügbar';
    } else {
      text = '🔒 Gesperrt';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _getStatusColor(),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (reward.isRedeemed) return Colors.green;
    if (reward.isUnlocked) return Colors.amber;
    return Colors.grey;
  }
}