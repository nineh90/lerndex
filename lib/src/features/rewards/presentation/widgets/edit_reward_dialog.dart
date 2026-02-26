import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/domain/child_model.dart';
import '../../domain/reward_model.dart';
import '../../domain/reward_enums.dart';

// ============================================================================
// EDIT REWARD DIALOG — Vollständig mit Trigger-Auswahl
// ============================================================================

class EditRewardDialog extends ConsumerStatefulWidget {
  final ChildModel child;
  final String userId;
  final RewardModel reward;

  const EditRewardDialog({
    super.key,
    required this.child,
    required this.userId,
    required this.reward,
  });

  @override
  ConsumerState<EditRewardDialog> createState() => _EditRewardDialogState();
}

class _EditRewardDialogState extends ConsumerState<EditRewardDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _rewardController;
  late TextEditingController _triggerValueController;

  late RewardTrigger _selectedTrigger;
  int? _triggerValue;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.reward.title);
    _descriptionController = TextEditingController(
      text: widget.reward.description,
    );
    _rewardController = TextEditingController(text: widget.reward.reward);
    _selectedTrigger = widget.reward.trigger;

    // Aktuellen Trigger-Wert aus dem Reward ermitteln
    final currentValue =
        widget.reward.requiredLevel ??
        widget.reward.requiredXP ??
        widget.reward.requiredStars ??
        widget.reward.requiredStreak ??
        widget.reward.requiredQuizCount;
    _triggerValue = currentValue;
    _triggerValueController = TextEditingController(
      text: currentValue != null ? currentValue.toString() : '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _rewardController.dispose();
    _triggerValueController.dispose();
    super.dispose();
  }

  bool _needsTriggerValue(RewardTrigger trigger) {
    return trigger != RewardTrigger.manual &&
        trigger != RewardTrigger.perfectQuiz;
  }

  String _getTriggerValueLabel(RewardTrigger trigger) {
    switch (trigger) {
      case RewardTrigger.level:
        return 'Erforderliches Level';
      case RewardTrigger.xp:
        return 'Erforderliche XP';
      case RewardTrigger.stars:
        return 'Erforderliche Sterne';
      case RewardTrigger.streak:
        return 'Erforderliche Streak-Tage';
      case RewardTrigger.quizCount:
        return 'Erforderliche Quiz-Anzahl';
      default:
        return 'Wert';
    }
  }

  String _getTriggerHelperText() {
    switch (_selectedTrigger) {
      case RewardTrigger.level:
        return 'Aktuell: Level ${widget.child.level}';
      case RewardTrigger.xp:
        return 'Aktuell: ${widget.child.xp} XP';
      case RewardTrigger.stars:
        return 'Aktuell: ${widget.child.stars} Sterne';
      case RewardTrigger.streak:
        return 'Aktuell: ${widget.child.streak ?? 0} Tage';
      case RewardTrigger.quizCount:
        return 'Aktuell: ${widget.child.totalQuizzes ?? 0} Quizze';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.amber,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Belohnung bearbeiten',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Titel
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titel *',
                    hintText: 'z.B. Extra Spielzeit',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Bitte Titel eingeben' : null,
                ),
                const SizedBox(height: 12),

                // Beschreibung
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // Belohnungstext
                TextFormField(
                  controller: _rewardController,
                  decoration: const InputDecoration(
                    labelText: 'Belohnung *',
                    hintText: 'z.B. 30 Min extra Tablet-Zeit',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.card_giftcard),
                  ),
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Bitte Belohnung eingeben'
                      : null,
                ),
                const SizedBox(height: 12),

                // Trigger-Bedingung
                const Text(
                  'Freigabe-Bedingung',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<RewardTrigger>(
                  value: _selectedTrigger,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                  items: RewardTrigger.values
                      .where((t) => t != RewardTrigger.avatarUnlock)
                      .map((trigger) {
                        return DropdownMenuItem(
                          value: trigger,
                          child: Text(trigger.displayName),
                        );
                      })
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedTrigger = value!;
                      _triggerValue = null;
                      _triggerValueController.clear();
                    });
                  },
                ),
                const SizedBox(height: 12),

                // Trigger-Wert
                if (_needsTriggerValue(_selectedTrigger)) ...[
                  TextFormField(
                    controller: _triggerValueController,
                    decoration: InputDecoration(
                      labelText: _getTriggerValueLabel(_selectedTrigger),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.numbers),
                      helperText: _getTriggerHelperText(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Bitte Wert eingeben';
                      }
                      final intValue = int.tryParse(value);
                      if (intValue == null || intValue <= 0) {
                        return 'Ungültiger Wert';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      _triggerValue = int.tryParse(value);
                    },
                  ),
                ],

                const SizedBox(height: 20),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isUpdating
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _updateReward,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isUpdating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save, size: 18),
                      label: const Text('Speichern'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateReward() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    try {
      // Trigger-Wert-Felder aufbauen
      final updateData = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'reward': _rewardController.text.trim(),
        'trigger': _selectedTrigger.toFirestore(),
        // System-Belohnungen werden nach Bearbeitung zu eigenen Belohnungen
        'type': 'parent',
        // Status auf pending zurücksetzen wenn Trigger geändert und nicht manual
        if (_selectedTrigger != RewardTrigger.manual) 'status': 'pending',
        if (_selectedTrigger == RewardTrigger.manual) 'status': 'approved',
        if (_selectedTrigger == RewardTrigger.manual)
          'approvedAt': FieldValue.serverTimestamp(),
        // Alle trigger-spezifischen Felder löschen/setzen
        'requiredLevel': FieldValue.delete(),
        'requiredXP': FieldValue.delete(),
        'requiredStars': FieldValue.delete(),
        'requiredStreak': FieldValue.delete(),
        'requiredQuizCount': FieldValue.delete(),
      };

      // Aktiven Trigger-Wert setzen
      if (_triggerValue != null) {
        switch (_selectedTrigger) {
          case RewardTrigger.level:
            updateData['requiredLevel'] = _triggerValue;
            break;
          case RewardTrigger.xp:
            updateData['requiredXP'] = _triggerValue;
            break;
          case RewardTrigger.stars:
            updateData['requiredStars'] = _triggerValue;
            break;
          case RewardTrigger.streak:
            updateData['requiredStreak'] = _triggerValue;
            break;
          case RewardTrigger.quizCount:
            updateData['requiredQuizCount'] = _triggerValue;
            break;
          default:
            break;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('children')
          .doc(widget.child.id)
          .collection('rewards')
          .doc(widget.reward.id)
          .update(updateData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Belohnung aktualisiert'),
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
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
}
