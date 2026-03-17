import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/data/profile_repository.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';

/// Wird nach einem Upgrade angezeigt wenn nicht alle pausierten Kinder
/// reaktiviert werden können (z.B. Solo → Duo mit 4 Kindern).
/// Der User wählt welche Kinder reaktiviert werden sollen.
class ChildReactivationScreen extends ConsumerStatefulWidget {
  /// Alle pausierten Kinder
  final List<ChildModel> pausedChildren;

  /// Wie viele dürfen zusätzlich reaktiviert werden
  final int slotsAvailable;

  const ChildReactivationScreen({
    super.key,
    required this.pausedChildren,
    required this.slotsAvailable,
  });

  @override
  ConsumerState<ChildReactivationScreen> createState() =>
      _ChildReactivationScreenState();
}

class _ChildReactivationScreenState
    extends ConsumerState<ChildReactivationScreen> {
  final Set<String> _selected = {};
  bool _saving = false;

  bool get _limitReached => _selected.length >= widget.slotsAvailable;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Nicht wegklickbar — User muss eine Auswahl treffen
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3E8FF),
        appBar: AppBar(
          title: const Text('Kinder reaktivieren'),
          backgroundColor: const Color(0xFF6B21A8),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              child: Column(
                children: [
                  const Icon(
                    Icons.upgrade_rounded,
                    size: 48,
                    color: Color(0xFF6B21A8),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Upgrade erfolgreich! 🎉',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B21A8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Du hast ${widget.slotsAvailable} freie ${widget.slotsAvailable == 1 ? 'Platz' : 'Plätze'}.\n'
                    'Wähle ${widget.slotsAvailable == 1 ? 'ein Kind' : '${widget.slotsAvailable} Kinder'} zum Reaktivieren aus.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  // Fortschrittsanzeige
                  Text(
                    '${_selected.length} / ${widget.slotsAvailable} ausgewählt',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _limitReached
                          ? const Color(0xFF6B21A8)
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),

            // ── Kinderliste ───────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.pausedChildren.length,
                itemBuilder: (context, index) {
                  final child = widget.pausedChildren[index];
                  final isSelected = _selected.contains(child.id);
                  final isDisabled = _limitReached && !isSelected;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: isSelected
                          ? const BorderSide(color: Color(0xFF6B21A8), width: 2)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isDisabled
                            ? Colors.grey.shade300
                            : const Color(0xFF6B21A8),
                        radius: 22,
                        backgroundImage: child.selectedAvatar != null
                            ? AssetImage(
                                'assets/images/${child.selectedAvatar}.png',
                              )
                            : null,
                        child: child.selectedAvatar == null
                            ? Text(
                                child.name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        child.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDisabled ? Colors.grey : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        '${child.schoolType} • Klasse ${child.grade}',
                        style: TextStyle(
                          color: isDisabled
                              ? Colors.grey.shade400
                              : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: const Color(0xFF6B21A8),
                        onChanged: isDisabled
                            ? null
                            : (val) {
                                setState(() {
                                  if (val == true) {
                                    _selected.add(child.id);
                                  } else {
                                    _selected.remove(child.id);
                                  }
                                });
                              },
                      ),
                      onTap: isDisabled
                          ? null
                          : () {
                              setState(() {
                                if (isSelected) {
                                  _selected.remove(child.id);
                                } else {
                                  _selected.add(child.id);
                                }
                              });
                            },
                    ),
                  );
                },
              ),
            ),

            // ── Bestätigen Button ─────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selected.isEmpty || _saving ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B21A8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _selected.isEmpty
                                ? 'Kinder auswählen'
                                : '${_selected.length} ${_selected.length == 1 ? 'Kind' : 'Kinder'} reaktivieren',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(profileRepositoryProvider);
      for (final id in _selected) {
        await repo.reactivateChild(id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
