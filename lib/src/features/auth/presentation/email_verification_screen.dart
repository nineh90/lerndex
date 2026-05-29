import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import 'setup_dialog.dart';

/// E-Mail Verifizierungs-Screen
/// Erscheint nach der Registrierung per E-Mail
/// Prüft automatisch alle 3 Sekunden ob die E-Mail bestätigt wurde
class EmailVerificationScreen extends ConsumerStatefulWidget {
  final String displayName;

  const EmailVerificationScreen({super.key, required this.displayName});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  Timer? _checkTimer;
  bool _isResending = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startCheckTimer();
    _startResendCountdown();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Prüft alle 3 Sekunden ob E-Mail verifiziert wurde
  void _startCheckTimer() {
    _checkTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final verified = await ref.read(authRepositoryProvider).isEmailVerified();
      if (verified && mounted) {
        _checkTimer?.cancel();
        // Weiter zum Onboarding
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SetupDialog()),
        );
      }
    });
  }

  /// 60-Sekunden-Countdown bis "Erneut senden" verfügbar ist
  void _startResendCountdown() {
    _resendCountdown = 60;
    _canResend = false;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          _canResend = true;
          _countdownTimer?.cancel();
        }
      });
    });
  }

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✉️ E-Mail wurde erneut gesendet!'),
            backgroundColor: Colors.green,
          ),
        );
        _startResendCountdown();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _cancelAndSignOut() async {
    await ref.read(authRepositoryProvider).signOut();
    if (mounted) Navigator.of(context).pop();
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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),

                const Text(
                  'E-Mail bestätigen',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Hallo ${widget.displayName.split(' ').first}! 👋\n\nWir haben eine Bestätigungs-Mail an dich gesendet. Bitte klicke auf den Link in der E-Mail um fortzufahren.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 40),

                // Auto-Check Indikator
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF6B21A8),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Warte auf Bestätigung...',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Erneut senden
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: (_canResend && !_isResending)
                                ? _resendEmail
                                : null,
                            icon: _isResending
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_outlined),
                            label: Text(
                              _canResend
                                  ? 'E-Mail erneut senden'
                                  : 'Erneut senden ($_resendCountdown s)',
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF6B21A8)),
                              foregroundColor: const Color(0xFF6B21A8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Abbrechen
                TextButton(
                  onPressed: _cancelAndSignOut,
                  child: const Text(
                    'Abbrechen und zurück zum Login',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
