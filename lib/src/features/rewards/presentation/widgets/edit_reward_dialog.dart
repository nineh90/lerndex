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
        return 'Erforderliche Tage am Stück';
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
        return 'Sterne werden nicht mehr vergeben';
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
                        color: const Color(0xFFEDE7FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Color(0xFF7C4DFF),
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
                  initialValue: _selectedTrigger,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                  items: RewardTrigger.values
                      .where((t) => t != RewardTrigger.avatarUnlock)
                      // Manual ausgeblendet, siehe create_reward_dialog.
                      // Existierende manual-Rewards können trotzdem
                      // editiert werden, wenn _selectedTrigger == manual ist,
                      // wird der Wert beim Speichern unverändert übernommen.
                      .where(
                        (t) =>
                            t != RewardTrigger.manual ||
                            widget.reward.trigger == RewardTrigger.manual,
                      )
                      // Sterne gibt es nicht mehr; nur zeigen, damit eine
                      // alte Sterne-Belohnung umgestellt werden kann.
                      .where(
                        (t) =>
                            t != RewardTrigger.stars ||
                            widget.reward.trigger == RewardTrigger.stars,
                      )
                      .map((trigger) {
                        return DropdownMenuItem(
                          value: trigger,
                          child: Text(
                            trigger == RewardTrigger.stars
                                ? 'Sterne (gibt es nicht mehr)'
                                : trigger.displayName,
                          ),
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
                      if (_selectedTrigger == RewardTrigger.stars) {
                        return 'Sterne gibt es nicht mehr. '
                            'Bitte wähle eine andere Bedingung.';
                      }
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
                        backgroundColor: const Color(0xFF7C4DFF),
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
      final updateData = buildRewardEditUpdate(
        original: widget.reward,
        currentXP: widget.child.xp,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        reward: _rewardController.text.trim(),
        trigger: _selectedTrigger,
        triggerValue: _triggerValue,
      );

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
          const SnackBar(
            content: Text(
              'Die Belohnung konnte nicht gespeichert werden. '
              'Bitte prüfe die Internetverbindung und versuche es noch einmal.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
}

/// Felder für das Speichern einer bearbeiteten Belohnung.
///
/// Status, Bedingung und XP-Startwert ändern sich nur, wenn sich die
/// Bedingung ändert: Wer nur den Text anpasst, sperrt eine freigeschaltete
/// oder eingelöste Belohnung nicht wieder. Bei einem neuen XP-Ziel zählt
/// (wie beim Anlegen) nur, was ab jetzt dazukommt ([currentXP]).
Map<String, dynamic> buildRewardEditUpdate({
  required RewardModel original,
  required int currentXP,
  required String title,
  required String description,
  required String reward,
  required RewardTrigger trigger,
  required int? triggerValue,
}) {
  final originalValue =
      original.requiredLevel ??
      original.requiredXP ??
      original.requiredStars ??
      original.requiredStreak ??
      original.requiredQuizCount;
  // Status nur zurücksetzen, wenn sich die Bedingung ändert. Sonst würde
  // jede Textänderung eine freigeschaltete oder eingelöste Belohnung
  // wieder sperren (und sie neu auslösen).
  final triggerChanged =
      trigger != original.trigger ||
      ((trigger != RewardTrigger.manual &&
              trigger != RewardTrigger.perfectQuiz) &&
          triggerValue != originalValue);

  final updateData = <String, dynamic>{
    'title': title,
    'description': description,
    'reward': reward,
  };

  if (triggerChanged) {
    updateData.addAll({
      'trigger': trigger.toFirestore(),
      if (trigger != RewardTrigger.manual) 'status': 'pending',
      if (trigger == RewardTrigger.manual) 'status': 'approved',
      if (trigger == RewardTrigger.manual)
        'approvedAt': FieldValue.serverTimestamp(),
      // Neue Bedingung: ein früheres Zurückziehen gilt nicht mehr
      'withdrawn': FieldValue.delete(),
      // Alle trigger-spezifischen Felder löschen/setzen
      'requiredLevel': FieldValue.delete(),
      'requiredXP': FieldValue.delete(),
      'requiredStars': FieldValue.delete(),
      'requiredStreak': FieldValue.delete(),
      'requiredQuizCount': FieldValue.delete(),
      // XP-Ziel zählt wie beim Anlegen ab dem aktuellen Stand
      'baselineXP': trigger == RewardTrigger.xp
          ? currentXP
          : FieldValue.delete(),
    });

    // Aktiven Trigger-Wert setzen
    if (triggerValue != null) {
      switch (trigger) {
        case RewardTrigger.level:
          updateData['requiredLevel'] = triggerValue;
          break;
        case RewardTrigger.xp:
          updateData['requiredXP'] = triggerValue;
          break;
        case RewardTrigger.stars:
          updateData['requiredStars'] = triggerValue;
          break;
        case RewardTrigger.streak:
          updateData['requiredStreak'] = triggerValue;
          break;
        case RewardTrigger.quizCount:
          updateData['requiredQuizCount'] = triggerValue;
          break;
        default:
          break;
      }
    }
  }

  return updateData;
}
