import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/pin_repository.dart';
import '../../auth/data/auth_repository.dart';

/// Dialog zum Eingeben des PINs
class PinInputDialog extends ConsumerStatefulWidget {
  const PinInputDialog({super.key});

  @override
  ConsumerState<PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends ConsumerState<PinInputDialog> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  int _attempts = 0;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyPin() async {
    final pin = _pinController.text;

    if (pin.length < 4) {
      setState(() => _errorMessage = 'PIN zu kurz');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = ref.read(authStateChangesProvider).value;
      if (user == null) throw Exception('Nicht eingeloggt');

      final isValid = await ref.read(pinRepositoryProvider).verifyPin(user.uid, pin);

      if (mounted) {
        if (isValid) {
          Navigator.of(context).pop(true); // PIN korrekt
        } else {
          _attempts++;
          setState(() {
            _errorMessage = 'Falscher PIN! (Versuch $_attempts/3)';
            _isLoading = false;
          });
          _pinController.clear();

          if (_attempts >= 3) {
            Navigator.of(context).pop(false); // Zu viele Versuche
          }
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.deepPurple),
          SizedBox(width: 8),
          Text('Eltern-PIN eingeben'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Gib deinen PIN ein, um das Eltern-Dashboard zu öffnen.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),

          // PIN Eingabe
          TextField(
            controller: _pinController,
            decoration: InputDecoration(
              labelText: 'PIN',
              prefixIcon: const Icon(Icons.pin),
              border: const OutlineInputBorder(),
              errorText: _errorMessage,
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            onSubmitted: (_) => _verifyPin(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verifyPin,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Text('Entsperren'),
        ),
      ],
    );
  }
}