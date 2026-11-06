import 'package:flutter/material.dart';

import '../../auth/presentation/login_screen.dart';
import '../../auth/presentation/register_screen.dart';
import '../../../shared/legal_links.dart';

/// QR-Code „Eltern verbinden“ gescannt, aber noch nicht angemeldet. Der Code
/// ist gemerkt (ParentLinkRepository.rememberPending) und wird nach der
/// Anmeldung im Familien-Dashboard eingelöst.
class ParentLinkIntroScreen extends StatelessWidget {
  const ParentLinkIntroScreen({super.key});

  static const _purple = Color(0xFF6B21A8);

  @override
  Widget build(BuildContext context) {
    void go(Widget screen) => Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Lerndex'),
        backgroundColor: _purple,
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
                  const Text(
                    '👨‍👩‍👧',
                    style: TextStyle(fontSize: 52),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mit Ihrem Kind verbinden',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Melden Sie sich mit Ihrem Lerndex-Konto an oder legen Sie '
                    'kostenlos eins an. Danach ist Ihr Kind automatisch '
                    'verbunden: Sie sehen, was es gelernt hat, und können '
                    'Belohnungen festlegen. Für Kinder einer Schule brauchen '
                    'Sie kein Abo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[800], fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => go(const RegisterScreen()),
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Konto anlegen'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => go(const LoginScreen()),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Ich habe schon ein Konto'),
                  ),
                  const SizedBox(height: 24),
                  const LegalFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
