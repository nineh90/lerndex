import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../splash/splash_screen.dart';
import '../../../shared/app_links.dart';
import '../data/child_device_repository.dart';
import 'qr_scan_screen.dart';
import '../../../shared/legal_links.dart';
import '../../../shared/user_message.dart';

/// „Ich bin ein Kind“: Kopplungscode eintippen, den die Eltern im
/// Elternbereich (Kind bearbeiten → Eigenes Gerät) erzeugt haben.
class ChildPairingScreen extends ConsumerStatefulWidget {
  const ChildPairingScreen({super.key, this.initialError});

  /// Fehler aus einem Koppel-Link (z.B. abgelaufen), der hier angezeigt wird.
  final String? initialError;

  @override
  ConsumerState<ChildPairingScreen> createState() => _ChildPairingScreenState();
}

class _ChildPairingScreenState extends ConsumerState<ChildPairingScreen> {
  final _controller = TextEditingController();
  late String? _error = widget.initialError;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length != 8) {
      setState(() => _error = 'Der Code hat 8 Zeichen, z.B. K7MX-Q2PA.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(childDeviceRepositoryProvider).redeemPairingCode(code);
      if (!mounted) return;
      // Der Startbildschirm erkennt das Kindergerät und öffnet das Dashboard
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LerndexSplashScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userMessage(e);
        _loading = false;
      });
    }
  }

  /// Nur in der App: QR-Code der Eltern (…/k/CODE) oder Schülerkarte
  /// (…/s/TOKEN) scannen. Der Startbildschirm löst den Link ein wie im
  /// Browser; ein reiner Code landet im Eingabefeld.
  Future<void> _scan() async {
    final text = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (text == null || !mounted) return;
    final path = lerndexLinkPath(text);
    if (path != null) {
      openLinkPath(path);
      return;
    }
    final code = text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (code.length == 8) {
      _controller.text = '${code.substring(0, 4)}-${code.substring(4)}';
      await _submit();
      return;
    }
    setState(
      () => _error =
          'Das ist kein Lerndex-Code. Frag deine Eltern '
          'nach dem QR-Code unter „Eigenes Gerät“.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ich bin ein Kind'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                '🔑',
                style: TextStyle(fontSize: 56),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                kIsWeb
                    ? 'Gib den Code ein, den deine Eltern dir zeigen.'
                    : 'Scanne den QR-Code, den deine Eltern dir zeigen.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? 'Deine Eltern finden ihn im Elternbereich bei deinem '
                          'Namen unter „Eigenes Gerät“.'
                    : 'Deine Eltern finden ihn im Elternbereich bei deinem '
                          'Namen unter „Eigenes Gerät“. Hast du eine '
                          'Schülerkarte von der Schule? Die kannst du auch '
                          'scannen.',
                style: TextStyle(color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (!kIsWeb) ...[
                FilledButton.icon(
                  onPressed: _loading ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text(
                    'QR-Code scannen',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6B21A8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'oder den Code eintippen:',
                  style: TextStyle(color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _controller,
                // In der App zuerst der Scanner, im Browser gleich tippen
                autofocus: kIsWeb,
                enabled: !_loading,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 9,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                ],
                style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'K7MX-Q2PA',
                  counterText: '',
                  errorText: _error,
                  errorMaxLines: 3,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6B21A8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Los geht\'s', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),
              const LegalFooter(adultGate: true),
            ],
          ),
        ),
      ),
    );
  }
}
