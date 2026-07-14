import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/data/profile_repository.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';

/// Wird gezeigt wenn ein User mehr Kinder hat als sein aktueller Plan erlaubt.
/// Beispiel: War auf Family (4 Kinder), jetzt auf Solo (1 Kind) gewechselt.
/// Der User muss Kinder auswählen die deaktiviert werden sollen.
///
/// Deaktivierte Kinder werden NICHT gelöscht — sie bekommen ein Feld
/// 'isActive: false' und sind im Dashboard nicht mehr sichtbar.
/// Bei einem Upgrade können sie jederzeit wiederhergestellt werden.
class ChildLimitExceededScreen extends ConsumerStatefulWidget {
  final List<ChildModel> children;
  final int allowedCount;

  const ChildLimitExceededScreen({
    super.key,
    required this.children,
    required this.allowedCount,
  });

  @override
  ConsumerState<ChildLimitExceededScreen> createState() =>
      _ChildLimitExceededScreenState();
}

class _ChildLimitExceededScreenState
    extends ConsumerState<ChildLimitExceededScreen> {
  // Kinder die BEHALTEN werden (max = allowedCount)
  final Set<String> _keptChildIds = {};
  bool _isSaving = false;

  static const _purple = Color(0xFF6B21A8);

  int get _toDeactivate => widget.children.length - widget.allowedCount;

  bool get _selectionValid => _keptChildIds.length == widget.allowedCount;

  @override
  void initState() {
    super.initState();
    // Standardmäßig die ersten N Kinder behalten
    for (int i = 0; i < widget.allowedCount; i++) {
      _keptChildIds.add(widget.children[i].id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abo-Änderung'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Info-Box ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange.shade700,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Dein neuer Plan erlaubt nur ${widget.allowedCount} '
                        '${widget.allowedCount == 1 ? "Kind" : "Kinder"}. '
                        'Wähle aus welche ${widget.allowedCount == 1 ? "das Kind" : "Kinder"} '
                        'aktiv bleiben sollen. Die anderen werden pausiert — '
                        'ihre Daten bleiben erhalten.',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Wähle ${widget.allowedCount} '
                '${widget.allowedCount == 1 ? "Kind" : "Kinder"} die aktiv bleiben:',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              // ── Kinderliste ───────────────────────────────────────────────
              Expanded(
                child: ListView.separated(
                  itemCount: widget.children.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final child = widget.children[index];
                    final isKept = _keptChildIds.contains(child.id);
                    final canSelect =
                        !isKept && _keptChildIds.length < widget.allowedCount;

                    return _ChildSelectionCard(
                      child: child,
                      isKept: isKept,
                      canSelect: canSelect,
                      onTap: () {
                        setState(() {
                          if (isKept) {
                            _keptChildIds.remove(child.id);
                          } else if (canSelect) {
                            _keptChildIds.add(child.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // ── Zähler ───────────────────────────────────────────────────
              Text(
                '${_keptChildIds.length} von ${widget.allowedCount} ausgewählt',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _selectionValid ? _purple : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 12),

              // ── Bestätigen ────────────────────────────────────────────────
              ElevatedButton(
                onPressed: (_selectionValid && !_isSaving) ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        '$_toDeactivate '
                        '${_toDeactivate == 1 ? "Kind" : "Kinder"} pausieren & weiter',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _isSaving = true);

    try {
      final repo = ref.read(profileRepositoryProvider);

      // Kinder die NICHT behalten werden → deaktivieren
      final toDeactivate = widget.children
          .where((c) => !_keptChildIds.contains(c.id))
          .toList();

      for (final child in toDeactivate) {
        await repo.deactivateChild(child.id);
      }

      if (mounted) {
        // Screen schließen — FamilyDashboard baut sich neu
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// =============================================================================
// KIND-KARTE
// =============================================================================

class _ChildSelectionCard extends StatelessWidget {
  final ChildModel child;
  final bool isKept;
  final bool canSelect;
  final VoidCallback onTap;

  const _ChildSelectionCard({
    required this.child,
    required this.isKept,
    required this.canSelect,
    required this.onTap,
  });

  static const _purple = Color(0xFF6B21A8);

  @override
  Widget build(BuildContext context) {
    final isDisabled = !isKept && !canSelect;

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isKept
              ? const Color(0xFFF3E8FF)
              : isDisabled
              ? Colors.grey.shade100
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isKept ? _purple : Colors.grey.shade300,
            width: isKept ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: _purple,
              backgroundImage: child.selectedAvatar != null
                  ? AssetImage('assets/images/${child.selectedAvatar}.webp')
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
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    child.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDisabled ? Colors.grey : Colors.black87,
                    ),
                  ),
                  Text(
                    '${child.schoolType} • Klasse ${child.grade} • Lvl ${child.level}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDisabled
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Status-Icon
            Icon(
              isKept ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isKept ? _purple : Colors.grey.shade400,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}
