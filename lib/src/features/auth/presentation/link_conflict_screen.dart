import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../splash/splash_screen.dart';
import '../data/child_device_repository.dart';
import '../../../shared/user_message.dart';
import 'child_login_confirm.dart';
import 'sign_out.dart';

/// Jemand scannt einen Koppel-Code (…/k/CODE) oder eine Schülerkarte
/// (…/s/TOKEN), während auf dem Gerät schon ein Eltern- oder Lehrerkonto
/// angemeldet ist. Statt den Link still zu ignorieren, wird nachgefragt.
class LinkConflictScreen extends ConsumerStatefulWidget {
  const LinkConflictScreen({
    super.key,
    required this.accountLabel,
    this.pairingCode,
    this.cardToken,
  }) : assert((pairingCode == null) != (cardToken == null));

  /// Wer gerade angemeldet ist (E-Mail)
  final String accountLabel;
  final String? pairingCode;
  final String? cardToken;

  @override
  ConsumerState<LinkConflictScreen> createState() => _LinkConflictScreenState();
}

class _LinkConflictScreenState extends ConsumerState<LinkConflictScreen> {
  bool _busy = false;
  String? _error;

  bool get _isCard => widget.cardToken != null;

  void _restart() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LerndexSplashScreen()),
      (_) => false,
    );
  }

  /// Erst den Code bzw. die Karte prüfen und nachfragen, dann abmelden und
  /// als Kind anmelden. Scheitert die Prüfung, bleibt das Konto angemeldet.
  Future<void> _switch() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(childDeviceRepositoryProvider);
    try {
      final login = _isCard
          ? await repo.checkStudentCard(widget.cardToken!)
          : await repo.checkPairingCode(widget.pairingCode!);
      if (!mounted) return;
      if (!await confirmChildLogin(context, login, isCard: _isCard)) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await signOutAccount(ref);
      await repo.signInAs(login);
      if (mounted) _restart();
    } catch (e) {
      // Ist schon abgemeldet, führt „Weiter“ zur Anmeldung
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isCard
        ? 'Als Schüler anmelden?'
        : 'Als Kindergerät einrichten?';
    final text = _isCard
        ? 'Du hast eine Anmeldekarte gescannt. Auf diesem Gerät ist aber '
              'gerade ${widget.accountLabel} angemeldet.'
        : 'Du hast den Code für ein Kindergerät gescannt. Auf diesem Gerät '
              'ist aber gerade ${widget.accountLabel} angemeldet.';
    final switchLabel = _isCard
        ? 'Abmelden und Schüler anmelden'
        : 'Abmelden und Kindergerät einrichten';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Lerndex'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isCard ? '🎒' : '📱',
                    style: const TextStyle(fontSize: 56),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    style: TextStyle(color: Colors.grey[800], fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_error == null)
                    FilledButton(
                      onPressed: _busy ? null : _switch,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6B21A8),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(switchLabel),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _restart,
                    child: Text(
                      _error == null ? 'Angemeldet bleiben' : 'Weiter',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
