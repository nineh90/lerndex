import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/pin_repository.dart';
import '../../auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';

/// Dialog zum Erstellen eines neuen PINs
class PinSetupDialog extends ConsumerStatefulWidget {
  const PinSetupDialog({super.key});

  @override
  ConsumerState<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends ConsumerState<PinSetupDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _setupPin() async {
    if (_isLoading) return; // kein doppeltes Speichern
    final pin = _pinController.text;
    final confirm = _confirmController.text;

    // Validierung
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _errorMessage = 'PIN muss 4-6 Ziffern haben');
      return;
    }

    if (pin != confirm) {
      setState(() => _errorMessage = 'PINs stimmen nicht überein');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = ref.read(authStateChangesProvider).value;
      if (user == null) throw Exception('Nicht eingeloggt');

      await ref.read(pinRepositoryProvider).setPin(user.ownerUid, pin);

      if (mounted) {
        Navigator.of(context).pop(true); // Erfolgreich
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Der PIN konnte nicht gespeichert werden. '
            'Bitte prüfe die Internetverbindung.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock, color: Colors.deepPurple),
          SizedBox(width: 8),
          Expanded(child: Text('Eltern-PIN erstellen')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Erstelle einen PIN, um das Eltern-Dashboard zu schützen.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 20),

            // PIN Eingabe
            TextField(
              controller: _pinController,
              decoration: InputDecoration(
                labelText: 'PIN (4-6 Ziffern)',
                prefixIcon: const Icon(Icons.pin),
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                errorMaxLines: 3,
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),

            // PIN Bestätigung
            TextField(
              controller: _confirmController,
              decoration: const InputDecoration(
                labelText: 'PIN bestätigen',
                prefixIcon: Icon(Icons.check),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _setupPin,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('PIN speichern'),
        ),
      ],
    );
  }
}
