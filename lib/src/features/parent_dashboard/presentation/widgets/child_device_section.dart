import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/child_device_repository.dart';
import '../../../auth/domain/account.dart';
import '../../../auth/domain/child_model.dart';

// ============================================================================
// EIGENES GERÄT FÜRS KIND (Elternbereich → Kind bearbeiten)
//
// Eltern erzeugen einen QR-Code. Das Kind scannt ihn mit der Kamera seines
// Handys/Tablets (öffnet die Web-App) oder tippt den Code in der App ein
// („Ich bin ein Kind“ auf der Anmeldeseite). Das Gerät ist danach nur als
// dieses Kind angemeldet – ohne Elternpasswort und ohne Elternbereich.
// ============================================================================

final _deviceCountProvider =
    StreamProvider.family<int, ({String ownerUid, String childId})>((ref, ids) {
      return ref
          .watch(childDeviceRepositoryProvider)
          .watchDeviceCount(ids.ownerUid, ids.childId);
    });

class ChildDeviceSection extends ConsumerWidget {
  const ChildDeviceSection({super.key, required this.child});

  final ChildModel child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    if (user == null) return const SizedBox.shrink();
    final count =
        ref
            .watch(
              _deviceCountProvider((
                ownerUid: user.ownerUid,
                childId: child.id,
              )),
            )
            .value ??
        0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${child.name} kann auf dem eigenen Handy, Tablet oder im '
            'Browser lernen. Das Gerät braucht dein Passwort nicht und hat '
            'keinen Elternbereich.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          Text(
            count == 0
                ? 'Noch kein Gerät verbunden'
                : count == 1
                ? '1 Gerät verbunden'
                : '$count Geräte verbunden',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PairingCodeDialog(child: child),
                ),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Gerät verbinden'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
              ),
              if (count > 0)
                OutlinedButton.icon(
                  onPressed: () => _confirmUnpair(context, ref),
                  icon: const Icon(Icons.phonelink_erase),
                  label: const Text('Alle abmelden'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Geräte abmelden?'),
        content: Text(
          'Alle Geräte, auf denen ${child.name} angemeldet ist, werden '
          'abgemeldet. Das kann bis zu einer Stunde dauern. Neu verbinden '
          'geht jederzeit mit einem neuen Code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(childDeviceRepositoryProvider).unpairDevices(child.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Geräte abgemeldet')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Abmelden hat nicht geklappt: $e')),
      );
    }
  }
}

/// Zeigt QR-Code, Code zum Abtippen und Restzeit. Läuft der Code ab, kann
/// man direkt einen neuen erzeugen.
class PairingCodeDialog extends ConsumerStatefulWidget {
  const PairingCodeDialog({super.key, required this.child});

  final ChildModel child;

  @override
  ConsumerState<PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends ConsumerState<PairingCodeDialog> {
  PairingCode? _code;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final code = await ref
          .read(childDeviceRepositoryProvider)
          .createPairingCode(widget.child.id);
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Code konnte nicht erstellt werden: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final remaining =
        code?.expiresAt.difference(DateTime.now()) ?? Duration.zero;
    final expired = code != null && remaining.isNegative;

    return AlertDialog(
      title: Text('Gerät für ${widget.child.name}'),
      content: SizedBox(
        width: 300,
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.red))
            : code == null
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mit der Kamera des Kinder-Handys scannen:',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Opacity(
                    opacity: expired ? 0.15 : 1,
                    child: QrImageView(
                      data: code.link.toString(),
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'oder in der App unter „Ich bin ein Kind“ eingeben:',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    code.display,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    expired
                        ? 'Abgelaufen'
                        : 'Gültig noch ${remaining.inMinutes}:'
                              '${(remaining.inSeconds % 60).toString().padLeft(2, '0')} '
                              'Minuten, nur einmal',
                    style: TextStyle(
                      fontSize: 12,
                      color: expired ? Colors.red : Colors.grey[600],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (code != null && !expired)
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code.link.toString()));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Link kopiert')));
            },
            child: const Text('Link kopieren'),
          ),
        if (_error != null || expired)
          TextButton(onPressed: _load, child: const Text('Neuer Code')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fertig'),
        ),
      ],
    );
  }
}
