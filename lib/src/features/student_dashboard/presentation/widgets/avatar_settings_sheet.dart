import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../auth/presentation/active_child_provider.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/child_model.dart';
import '../../domain/avatar_config.dart';

// ============================================================================
// AVATAR SETTINGS BOTTOM SHEET
// ============================================================================

class AvatarSettingsSheet extends ConsumerStatefulWidget {
  final ChildModel child;

  const AvatarSettingsSheet({super.key, required this.child});

  @override
  ConsumerState<AvatarSettingsSheet> createState() =>
      _AvatarSettingsSheetState();
}

class _AvatarSettingsSheetState extends ConsumerState<AvatarSettingsSheet> {
  bool _saving = false;

  Future<void> _selectAvatar(AvatarConfig avatar) async {
    if (_saving) return;
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    final currentAvatar = ref.read(activeChildProvider)?.selectedAvatar;
    final newValue = currentAvatar == avatar.id ? null : avatar.id;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(widget.child.id)
          .update({'selectedAvatar': newValue});

      ref.read(activeChildProvider.notifier).updateAvatar(newValue);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fehler beim Speichern')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Gibt den Lock-Hinweis für gesperrte Reward-Avatare zurück –
  /// für Achievement-Avatare spezifisch, für andere generisch.
  String _lockedLabel(AvatarConfig avatar) {
    switch (avatar.id) {
      case 'avatar-champion':
        return '🏆 Level 15';
      case 'avatar-legend':
        return '💎 Level 20';
      case 'avatar-xp-5k':
        return '⚡ 5.000 XP';
      case 'avatar-quiz-master':
        return '🎯 100 Quizze';
      case 'avatar-streak-uncommon':
        return '🔥 14 Tage';
      case 'avatar-streak-epic':
        return '🔥 28 Tage';
      case 'avatar-streak-legendary':
        return '🔥 42 Tage';
      default:
        return '🎁 Belohnung';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAvatar = ref.watch(activeChildProvider)?.selectedAvatar;
    final child = widget.child;
    final screenHeight = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Aktueller Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.deepPurple.shade100,
              backgroundImage: currentAvatar != null
                  ? AssetImage('assets/images/$currentAvatar.png')
                  : null,
              child: currentAvatar == null
                  ? Text(
                      child.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              child.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Level ${child.level} · ${child.stars} ⭐',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Avatar wählen',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            // Avatar Grid
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: kAvatars.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final avatar = kAvatars[index];
                  final isUnlocked = avatar.isRewardUnlock
                      ? child.unlockedAvatars.contains(avatar.id)
                      : child.level >= avatar.requiredLevel;
                  final isSelected = currentAvatar == avatar.id;

                  return GestureDetector(
                    onTap: isUnlocked ? () => _selectAvatar(avatar) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? avatar.color
                              : isUnlocked
                              ? avatar.color.withOpacity(0.4)
                              : Colors.grey.shade300,
                          width: isSelected ? 3 : 1.5,
                        ),
                        color: isSelected
                            ? avatar.color.withOpacity(0.1)
                            : Colors.grey.shade50,
                      ),
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              // ── Obere Badge-Zeile ──────────────────────
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isUnlocked
                                      ? avatar.color.withOpacity(0.12)
                                      : Colors.grey.shade200,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(14),
                                    topRight: Radius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  isUnlocked
                                      ? avatar.rarityLabel
                                      : avatar.isRewardUnlock
                                      ? _lockedLabel(avatar)
                                      : '🔒 Lvl ${avatar.requiredLevel}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isUnlocked
                                        ? avatar.color
                                        : Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              // ── Avatar-Bild ────────────────────────────
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    6,
                                    8,
                                    8,
                                  ),
                                  child: ColorFiltered(
                                    colorFilter: isUnlocked
                                        ? const ColorFilter.mode(
                                            Colors.transparent,
                                            BlendMode.multiply,
                                          )
                                        : const ColorFilter.matrix([
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0.2126,
                                            0.7152,
                                            0.0722,
                                            0,
                                            0,
                                            0,
                                            0,
                                            0,
                                            1,
                                            0,
                                          ]),
                                    child: Image.asset(
                                      'assets/images/${avatar.id}.png',
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.face,
                                        size: 42,
                                        color: avatar.color.withOpacity(
                                          isUnlocked ? 1.0 : 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Ausgewählt-Checkmark
                          if (isSelected)
                            Positioned(
                              top: 30,
                              right: 6,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: avatar.color,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}
