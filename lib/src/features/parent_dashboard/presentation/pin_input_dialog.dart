import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/pin_repository.dart';
import '../../auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';

/// Dialog zum Eingeben des PINs.
///
/// Fehlversuche zählt und sperrt der Server (nach 5 Fehlversuchen für
/// 5 Minuten, über alle Geräte). Der Dialog zählt deshalb nicht selbst mit,
/// sondern zeigt die Sperre an, wenn der Server sie meldet.
class PinInputDialog extends ConsumerStatefulWidget {
  const PinInputDialog({super.key});

  @override
  ConsumerState<PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends ConsumerState<PinInputDialog> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyPin() async {
    // Doppeltes Enter oder Tippen während der Prüfung: sonst zählt der
    // Server zwei Fehlversuche.
    if (_isLoading) return;

    final pin = _pinController.text;

    if (pin.length < 4) {
      setState(() => _errorMessage = 'Der PIN hat mindestens 4 Ziffern.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    String? error;
    try {
      final user = ref.read(authStateChangesProvider).value;
      if (user == null) {
        error = 'Du bist nicht mehr angemeldet. Bitte melde dich neu an.';
      } else {
        final isValid = await ref
            .read(pinRepositoryProvider)
            .verifyPin(user.ownerUid, pin);
        if (!mounted) return;
        if (isValid) {
          Navigator.of(context).pop(true); // PIN korrekt
          return;
        }
        error =
            'Falscher PIN. Nach 5 Fehlversuchen wird der PIN '
            'für 5 Minuten gesperrt.';
      }
    } on PinLockedException catch (e) {
      error = e.toString();
    } catch (_) {
      error =
          'Der PIN konnte nicht geprüft werden. '
          'Bitte prüfe die Internetverbindung.';
    }

    if (!mounted) return;
    _pinController.clear();
    setState(() {
      _errorMessage = error;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: AppColors.purple),
          SizedBox(width: 8),
          Expanded(child: Text('Eltern-PIN eingeben')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Gib deinen PIN ein, um das Eltern-Dashboard zu öffnen.',
            style: TextStyle(color: Colors.grey[700]),
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
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            readOnly: _isLoading,
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
            backgroundColor: AppColors.purple,
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
              : const Text('Entsperren'),
        ),
      ],
    );
  }
}
