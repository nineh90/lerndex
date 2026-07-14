import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/auth_repository.dart';
import 'register_screen.dart';
import 'setup_dialog.dart';
import 'family_dashboard_screen.dart';
// NEU: Subscription
import '../../subscription/data/subscription_provider.dart';

/// Login-Screen für bestehende Nutzer
/// Neue Nutzer werden zu RegisterScreen weitergeleitet
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Bitte fülle alle Felder aus.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await ref
          .read(authRepositoryProvider)
          .signInWithEmailAndPassword(email, password);

      if (!mounted) return;

      // NEU: RevenueCat identifizieren + Abo-Status laden
      final uid = credential.user?.uid;
      if (uid != null) {
        await ref.read(subscriptionServiceProvider).identifyUser(uid);
        await ref.read(subscriptionStatusProvider.notifier).refresh();
      }

      if (!mounted) return;

      final onboardingDone = await ref
          .read(authRepositoryProvider)
          .isOnboardingComplete();
      if (!mounted) return;

      if (!onboardingDone) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SetupDialog()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const FamilyDashboardScreen()),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleLogin() async {
    setState(() => _isGoogleLoading = true);
    try {
      final result = await ref.read(authRepositoryProvider).signInWithGoogle();
      await _continueAfterAuth(
        isNewUser: result.isNewUser,
        uid: result.credential.user?.uid,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _appleLogin() async {
    if (_isAppleLoading) return;
    setState(() => _isAppleLoading = true);
    try {
      final result = await ref.read(authRepositoryProvider).signInWithApple();
      await _continueAfterAuth(
        isNewUser: result.isNewUser,
        uid: result.credential.user?.uid,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isAppleLoading = false);
    }
  }

  /// Gemeinsamer Ablauf nach erfolgreichem Social-Login (Google/Apple):
  /// RevenueCat identifizieren, Abo laden, dann zu Onboarding oder Dashboard.
  Future<void> _continueAfterAuth({
    required bool isNewUser,
    required String? uid,
  }) async {
    if (!mounted) return;

    // RevenueCat identifizieren + Abo-Status laden
    if (uid != null) {
      await ref.read(subscriptionServiceProvider).identifyUser(uid);
      await ref.read(subscriptionStatusProvider.notifier).refresh();
    }
    if (!mounted) return;

    // Neuer User → erst Datenschutz-Zustimmung, dann Onboarding.
    // Über den Login-Screen können via Google/Apple neue Accounts entstehen,
    // die die Checkbox des Register-Screens nie gesehen haben (DSGVO Art. 7/8).
    if (isNewUser) {
      final accepted = await _askPrivacyConsent();
      if (!mounted) return;

      if (!accepted) {
        // Ohne Einwilligung kein Konto: eben angelegten Account wieder löschen.
        await ref.read(authRepositoryProvider).abortNewSocialAccount();
        if (mounted) {
          _showError(
            'Registrierung abgebrochen – ohne Zustimmung zur '
            'Datenschutzerklärung können wir kein Konto anlegen.',
          );
        }
        return;
      }

      await ref.read(authRepositoryProvider).recordPrivacyConsent();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupDialog()),
      );
      return;
    }

    // Bestehender User: Onboarding abgeschlossen?
    final onboardingDone =
        await ref.read(authRepositoryProvider).isOnboardingComplete();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            onboardingDone ? const FamilyDashboardScreen() : const SetupDialog(),
      ),
    );
  }

  /// Zeigt den Datenschutz-Zustimmungsdialog für neue Social-Login-Accounts.
  /// Gibt true zurück, wenn der Nutzer zugestimmt hat.
  Future<bool> _askPrivacyConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Datenschutz'),
        content: Text.rich(
          TextSpan(
            text: 'Um dein Lerndex-Konto anzulegen, brauchst du unsere ',
            children: [
              TextSpan(
                text: 'Datenschutzerklärung',
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(
                    Uri.parse('https://www.lerndex.de/datenschutz.php'),
                    mode: LaunchMode.externalApplication,
                  ),
              ),
              const TextSpan(
                text:
                    ' gelesen und akzeptiert. Sie beschreibt u.a., wie die '
                    'Lerndaten deiner Kinder verarbeitet werden.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ablehnen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ich akzeptiere'),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Bitte gib zuerst deine E-Mail-Adresse ein.');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✉️ Passwort-Reset-Mail wurde gesendet!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B21A8), Color(0xFF7E22CE)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Text + Tutor: Stack nur um den Textbereich
                  SizedBox(
                    height: 180,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Image.asset(
                              'assets/images/lerndex_logo.webp',
                              width: 160,
                              height: 160,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ),
                        // Text — am unteren Rand des Tutors
                        const Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              Text(
                                'Lerndex',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Willkommen zurück!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Login-Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // E-Mail
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: 'E-Mail',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 16),

                          // Passwort
                          TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Passwort',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                          ),

                          // Passwort vergessen
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _forgotPassword,
                              child: const Text(
                                'Passwort vergessen?',
                                style: TextStyle(color: Color(0xFF6B21A8)),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Login-Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6B21A8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Anmelden',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Divider
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'oder',
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Google-Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: _isGoogleLoading ? null : _googleLogin,
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                              icon: _isGoogleLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Image.asset(
                                      'assets/images/google_logo.png',
                                      height: 22,
                                      width: 22,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.g_mobiledata,
                                        size: 24,
                                        color: Colors.red,
                                      ),
                                    ),
                              label: const Text(
                                'Mit Google anmelden',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),

                          // Apple-Button (nur iOS – auf iOS Pflicht wegen Google-Login)
                          if (Platform.isIOS) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: SignInWithAppleButton(
                                onPressed: _appleLogin,
                                text: 'Mit Apple anmelden',
                                height: 50,
                                style: SignInWithAppleButtonStyle.black,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),

                          // Zu Registrierung wechseln
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Noch kein Konto?',
                                style: TextStyle(color: Colors.grey),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Jetzt registrieren',
                                  style: TextStyle(
                                    color: Color(0xFF6B21A8),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
