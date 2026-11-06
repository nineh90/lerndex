import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/email_verification_screen.dart';
import '../../auth/presentation/sign_out.dart';
import '../../splash/splash_screen.dart';
import '../data/school_repository.dart';
import '../../../shared/user_message.dart';
import '../../../shared/legal_links.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';

/// Registrierung einer Schule über den Einladungslink von Lerndex
/// (…/schule/CODE): Die Schulleitung legt die Schule und ihr Konto an. Das
/// Konto ist ein reines Schulkonto (accountType "school", gesetzt von den
/// Cloud Functions) und verwaltet nur die Lehrkräfte. Lehrkräfte melden sich
/// mit QR-Karte + PIN an (TeacherCardScreen).
class SchoolSignupScreen extends ConsumerStatefulWidget {
  const SchoolSignupScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<SchoolSignupScreen> createState() => _SchoolSignupScreenState();
}

class _SchoolSignupScreenState extends ConsumerState<SchoolSignupScreen> {
  final _schoolName = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _privacyAccepted = false;
  bool _busy = false;
  bool _registering = false;
  String? _error;

  static const _purple = AppColors.purple;

  @override
  void dispose() {
    _schoolName.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _goToStart() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LerndexSplashScreen()),
      (_) => false,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _registering = false;
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Neues Konto anlegen und Schule gründen bzw. beitreten.
  Future<void> _register() async {
    final schoolName = _schoolName.text.trim();
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (schoolName.length < 3 || name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Bitte alle Felder ausfüllen.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Das Passwort braucht mindestens 8 Zeichen.');
      return;
    }
    if (!_privacyAccepted) {
      setState(() => _error = 'Bitte der Datenschutzerklärung zustimmen.');
      return;
    }

    _registering = true;
    await _run(() async {
      final auth = ref.read(authRepositoryProvider);
      // Schulkonto: im Browser nur für diesen Tab angemeldet (Schul-PCs)
      await auth.keepLoginInThisTabOnly();
      await auth.createUserWithEmailAndPassword(email, password, name);
      try {
        await auth.recordPrivacyConsent();
        await ref
            .read(schoolRepositoryProvider)
            .createSchool(code: widget.code, name: schoolName);
      } catch (_) {
        // Code ungültig o.ä.: kein Konto ohne Schule zurücklassen
        await auth.abortNewSocialAccount();
        await auth.keepLoginOnThisDevice();
        _registering = false;
        rethrow;
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              EmailVerificationScreen(displayName: name, schoolAccount: true),
        ),
        (_) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;
    const title = 'Schule bei Lerndex registrieren';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Lerndex für Schulen'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '🏫',
                    style: TextStyle(fontSize: 52),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    title,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (user != null && !_registering)
                    ..._signedIn(user.email ?? 'ein anderes Konto')
                  else
                    ..._form(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const LegalFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Schon jemand angemeldet (z.B. mit dem Elternkonto).
  List<Widget> _signedIn(String email) => [
    Text(
      'Sie sind gerade als $email angemeldet. Für die Schule legen Sie ein '
      'eigenes Konto an, getrennt von einem Elternkonto.',
      style: TextStyle(color: Colors.grey[800], fontSize: 15),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : () => _run(() => signOutAccount(ref)),
      style: FilledButton.styleFrom(
        backgroundColor: _purple,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: const Text('Abmelden und Schule registrieren'),
    ),
    TextButton(
      onPressed: _busy ? null : _goToStart,
      child: const Text('Abbrechen'),
    ),
  ];

  List<Widget> _form() => [
    Text(
      'Legen Sie die Schule und Ihr Konto als Schulleitung an. Danach legen '
      'Sie die Lehrkräfte an, jede bekommt eine QR-Karte zum Anmelden.',
      style: TextStyle(color: Colors.grey[800], fontSize: 15),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    _field(_schoolName, 'Name der Schule', hint: 'z.B. Grundschule am Wald'),
    const SizedBox(height: 12),
    _field(_name, 'Ihr Name', hint: 'Vor- und Nachname'),
    const SizedBox(height: 12),
    _field(
      _email,
      'E-Mail (am besten die dienstliche)',
      keyboard: TextInputType.emailAddress,
    ),
    const SizedBox(height: 12),
    _field(_password, 'Passwort (mindestens 8 Zeichen)', obscure: true),
    const SizedBox(height: 8),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _privacyAccepted,
          activeColor: _purple,
          onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                children: [
                  const TextSpan(text: 'Ich habe die '),
                  TextSpan(
                    text: 'Datenschutzerklärung',
                    style: const TextStyle(
                      color: _purple,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => openLegalLink(LegalLinks.privacy),
                  ),
                  const TextSpan(text: ' gelesen und stimme ihr zu.'),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: _busy ? null : _register,
      style: FilledButton.styleFrom(
        backgroundColor: _purple,
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
          : const Text('Schule registrieren'),
    ),
  ];

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
