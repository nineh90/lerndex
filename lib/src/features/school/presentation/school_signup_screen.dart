import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/email_verification_screen.dart';
import '../../auth/presentation/sign_out.dart';
import '../../splash/splash_screen.dart';
import '../data/school_repository.dart';
import 'school_section.dart' show schoolErrorText;

/// Registrierung über einen Einladungslink:
/// - Schule (…/schule/CODE, Link von Lerndex): Schulleitung legt die Schule
///   und ihr Schulkonto an.
/// - Lehrkraft (…/lehrer/CODE, Link der Schulleitung): neues Schulkonto oder
///   Beitritt mit einem bestehenden Lerndex-Konto.
///
/// Neue Konten sind reine Schulkonten: Die App zeigt ihnen nur den
/// Schulbereich (accountType "school", gesetzt von den Cloud Functions).
class SchoolSignupScreen extends ConsumerStatefulWidget {
  const SchoolSignupScreen({
    super.key,
    required this.code,
    required this.isTeacher,
  });

  final String code;
  final bool isTeacher;

  @override
  ConsumerState<SchoolSignupScreen> createState() => _SchoolSignupScreenState();
}

class _SchoolSignupScreenState extends ConsumerState<SchoolSignupScreen> {
  final _schoolName = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _privacyAccepted = false;
  bool _existingAccount = false;
  bool _busy = false;
  bool _registering = false;
  String? _error;

  static const _purple = Color(0xFF6B21A8);

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
      if (mounted) setState(() => _error = schoolErrorText(e));
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
    if ((!widget.isTeacher && schoolName.length < 3) ||
        name.isEmpty ||
        email.isEmpty) {
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
      await auth.createUserWithEmailAndPassword(email, password, name);
      try {
        await auth.recordPrivacyConsent();
        final school = ref.read(schoolRepositoryProvider);
        if (widget.isTeacher) {
          await school.joinSchool(widget.code, schoolAccount: true);
        } else {
          await school.createSchool(code: widget.code, name: schoolName);
        }
      } catch (_) {
        // Code ungültig o.ä.: kein Konto ohne Schule zurücklassen
        await auth.abortNewSocialAccount();
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

  /// Lehrkraft mit bestehendem Konto: anmelden und beitreten.
  Future<void> _loginAndJoin() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Bitte E-Mail und Passwort eingeben.');
      return;
    }
    await _run(() async {
      await ref
          .read(authRepositoryProvider)
          .signInWithEmailAndPassword(email, _password.text);
      await _joinWithCurrentAccount();
    });
  }

  Future<void> _joinWithCurrentAccount() async {
    final school = await ref
        .read(schoolRepositoryProvider)
        .joinSchool(widget.code);
    ref.invalidate(schoolMembershipProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Willkommen bei $school')),
    );
    _goToStart();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;
    final title = widget.isTeacher
        ? 'Einladung Ihrer Schule'
        : 'Schule bei Lerndex registrieren';

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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
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
      widget.isTeacher
          ? 'Sie sind gerade als $email angemeldet. Sie können mit diesem '
                'Konto beitreten (Ihr Elternbereich bleibt erhalten) oder ein '
                'eigenes Konto für die Schule anlegen.'
          : 'Sie sind gerade als $email angemeldet. Für die Schule legen Sie '
                'ein eigenes Konto an, getrennt von einem Elternkonto.',
      style: TextStyle(color: Colors.grey[800], fontSize: 15),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    if (widget.isTeacher)
      FilledButton(
        onPressed: _busy ? null : () => _run(_joinWithCurrentAccount),
        style: FilledButton.styleFrom(
          backgroundColor: _purple,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text('Mit diesem Konto beitreten'),
      ),
    const SizedBox(height: 8),
    OutlinedButton(
      onPressed: _busy
          ? null
          : () => _run(() async {
              await signOutAccount(ref);
            }),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: const Text('Abmelden und neues Konto anlegen'),
    ),
    TextButton(
      onPressed: _busy ? null : _goToStart,
      child: const Text('Abbrechen'),
    ),
  ];

  List<Widget> _form() {
    final login = widget.isTeacher && _existingAccount;
    return [
      Text(
        login
            ? 'Melden Sie sich mit Ihrem bestehenden Lerndex-Konto an. Danach '
                  'gehören Sie zur Schule, Ihr Elternbereich bleibt erhalten.'
            : widget.isTeacher
            ? 'Legen Sie Ihr Lerndex-Konto für die Schule an. Damit sehen Sie '
                  'alle Klassen Ihrer Schule.'
            : 'Legen Sie die Schule und Ihr Konto als Schulleitung an. '
                  'Danach können Sie Klassen anlegen und Lehrkräfte einladen.',
        style: TextStyle(color: Colors.grey[800], fontSize: 15),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      if (!widget.isTeacher) ...[
        _field(_schoolName, 'Name der Schule', hint: 'z.B. Grundschule am Wald'),
        const SizedBox(height: 12),
      ],
      if (!login) ...[
        _field(_name, 'Ihr Name', hint: 'Vor- und Nachname'),
        const SizedBox(height: 12),
      ],
      _field(
        _email,
        login ? 'E-Mail' : 'E-Mail (am besten die dienstliche)',
        keyboard: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      _field(
        _password,
        login ? 'Passwort' : 'Passwort (mindestens 8 Zeichen)',
        obscure: true,
      ),
      if (!login) ...[
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
                          ..onTap = () => launchUrl(
                            Uri.parse('https://www.lerndex.de/datenschutz.php'),
                          ),
                      ),
                      const TextSpan(text: ' gelesen und stimme ihr zu.'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : (login ? _loginAndJoin : _register),
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
            : Text(
                login
                    ? 'Anmelden und beitreten'
                    : widget.isTeacher
                    ? 'Konto anlegen'
                    : 'Schule registrieren',
              ),
      ),
      if (widget.isTeacher)
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _existingAccount = !_existingAccount;
                  _error = null;
                }),
          child: Text(
            _existingAccount
                ? 'Neues Konto für die Schule anlegen'
                : 'Ich habe schon ein Lerndex-Konto',
          ),
        ),
    ];
  }

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
