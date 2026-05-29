import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/domain/child_model.dart';
import '../../data/reward_service.dart';
import '../../domain/reward_enums.dart';
import '../../../student_dashboard/domain/avatar_config.dart';

// ============================================================================
// CREATE REWARD DIALOG
// ============================================================================

class CreateRewardDialog extends ConsumerStatefulWidget {
  final ChildModel child;
  final String userId;

  const CreateRewardDialog({
    super.key,
    required this.child,
    required this.userId,
  });

  @override
  ConsumerState<CreateRewardDialog> createState() => _CreateRewardDialogState();
}

class _CreateRewardDialogState extends ConsumerState<CreateRewardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rewardController = TextEditingController();

  RewardTrigger _selectedTrigger = RewardTrigger.level;
  int? _triggerValue;
  bool _isAvatarReward = false; // Toggle: Text-Belohnung vs. Avatar-Belohnung
  String? _selectedAvatarId;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _rewardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset + bottomPadding),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                '🎁 Neue Belohnung erstellen',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bitte Titel eingeben';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Beschreibung
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung (optional)',
                  hintText: 'Was muss erreicht werden?',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              // Belohnungs-Typ Toggle
              const Text(
                'Art der Belohnung',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isAvatarReward = false;
                        _selectedAvatarId = null;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: !_isAvatarReward
                              ? Colors.deepPurple.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !_isAvatarReward
                                ? Colors.deepPurple
                                : Colors.grey.shade300,
                            width: !_isAvatarReward ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.card_giftcard,
                              color: !_isAvatarReward
                                  ? Colors.deepPurple
                                  : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Eigene\nBelohnung',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: !_isAvatarReward
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: !_isAvatarReward
                                    ? Colors.deepPurple
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isAvatarReward = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _isAvatarReward
                              ? Colors.deepPurple.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isAvatarReward
                                ? Colors.deepPurple
                                : Colors.grey.shade300,
                            width: _isAvatarReward ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.face,
                              color: _isAvatarReward
                                  ? Colors.deepPurple
                                  : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Avatar\nfreischalten',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _isAvatarReward
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _isAvatarReward
                                    ? Colors.deepPurple
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Belohnungs-Inhalt: Text oder Avatar-Picker
              if (!_isAvatarReward)
                TextFormField(
                  controller: _rewardController,
                  decoration: const InputDecoration(
                    labelText: 'Belohnung *',
                    hintText: 'z.B. 30 Min extra Tablet-Zeit',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.card_giftcard),
                  ),
                  validator: (value) {
                    if (!_isAvatarReward && (value == null || value.isEmpty)) {
                      return 'Bitte Belohnung eingeben';
                    }
                    return null;
                  },
                )
              else ...[
                // Avatar-Picker Grid
                FormField<String>(
                  validator: (_) => _isAvatarReward && _selectedAvatarId == null
                      ? 'Bitte Avatar auswählen'
                      : null,
                  builder: (state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Avatar auswählen *',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: kAvatars
                            .where((a) => a.id.startsWith('avatar-gift'))
                            .length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.82,
                            ),
                        itemBuilder: (context, index) {
                          final avatar = kAvatars
                              .where((a) => a.id.startsWith('avatar-gift'))
                              .toList()[index];
                          final isSelected = _selectedAvatarId == avatar.id;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedAvatarId = avatar.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? avatar.color
                                      : avatar.color.withValues(alpha: 0.3),
                                  width: isSelected ? 3 : 1.5,
                                ),
                                color: isSelected
                                    ? avatar.color.withValues(alpha: 0.1)
                                    : Colors.grey.shade50,
                              ),
                              child: Stack(
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            10,
                                            8,
                                            4,
                                          ),
                                          child: Image.asset(
                                            'assets/images/${avatar.id}.png',
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.face,
                                              size: 40,
                                              color: avatar.color,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Text(
                                          avatar.rarityLabel,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: avatar.color,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      top: 5,
                                      right: 5,
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: avatar.color,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      if (state.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 12),
                          child: Text(
                            state.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Trigger Auswahl
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
                    // 'manual' = sofort verfügbar ohne Bedingung – das Kind
                    // sieht die Belohnung direkt als einlösbar im Dashboard.
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
                  });
                },
              ),
              const SizedBox(height: 12),

              // Trigger Value Input
              if (_needsTriggerValue(_selectedTrigger)) ...[
                TextFormField(
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

                    // Validierung
                    final validation = ref
                        .read(rewardServiceProvider)
                        .validateParentReward(
                          child: widget.child,
                          trigger: _selectedTrigger,
                          requiredLevel: _selectedTrigger == RewardTrigger.level
                              ? intValue
                              : null,
                          requiredXP: _selectedTrigger == RewardTrigger.xp
                              ? intValue
                              : null,
                          requiredStars: _selectedTrigger == RewardTrigger.stars
                              ? intValue
                              : null,
                        );

                    if (!validation.isValid) {
                      return validation.message;
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
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCreating
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.deepPurple),
                        foregroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createReward,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Belohnung erstellen',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _needsTriggerValue(RewardTrigger trigger) {
    return trigger != RewardTrigger.manual &&
        trigger != RewardTrigger.perfectQuiz &&
        trigger != RewardTrigger.avatarUnlock;
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
        return 'XP die das Kind noch sammeln muss (hat aktuell ${widget.child.xp} XP)';
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

  Future<void> _createReward() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final rewardData = {
        'childId': widget.child.id,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'type': 'parent',
        'trigger': _selectedTrigger.toFirestore(),
        'reward': _isAvatarReward
            ? '🎭 Avatar-Freischaltung'
            : _rewardController.text.trim(),
        'status': _selectedTrigger == RewardTrigger.manual
            ? 'approved'
            : 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': widget.userId,
        if (_isAvatarReward && _selectedAvatarId != null)
          'avatarUnlockId': _selectedAvatarId,
        if (_selectedTrigger == RewardTrigger.level)
          'requiredLevel': _triggerValue,
        if (_selectedTrigger == RewardTrigger.xp) 'requiredXP': _triggerValue,
        if (_selectedTrigger == RewardTrigger.xp) 'baselineXP': widget.child.xp,
        if (_selectedTrigger == RewardTrigger.stars)
          'requiredStars': _triggerValue,
        if (_selectedTrigger == RewardTrigger.streak)
          'requiredStreak': _triggerValue,
        if (_selectedTrigger == RewardTrigger.quizCount)
          'requiredQuizCount': _triggerValue,
        if (_selectedTrigger == RewardTrigger.manual)
          'approvedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('children')
          .doc(widget.child.id)
          .collection('rewards')
          .add(rewardData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Belohnung erstellt'),
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
        setState(() => _isCreating = false);
      }
    }
  }
}
