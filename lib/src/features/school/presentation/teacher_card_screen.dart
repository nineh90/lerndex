import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/sign_out.dart';
import '../data/school_repository.dart';
import 'school_home_screen.dart';
import 'school_section.dart' show schoolErrorText;

/// Lehrkraft scannt ihre QR-Karte (…/l/TOKEN): beim ersten Mal PIN
/// festlegen, danach PIN eingeben. Die PIN prüft der Server
/// (redeemTeacherCard), nach 5 Fehlversuchen ist die Karte 15 Minuten
/// gesperrt.
class TeacherCardScreen extends ConsumerStatefulWidget {
  const TeacherCardScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<TeacherCardScreen> createState() => _TeacherCardScreenState();
}

class _TeacherCardScreenState extends ConsumerState<TeacherCardScreen> {
  final _pin = TextEditingController();
  final _pinRepeat = TextEditingController();
  Future<({bool pinSet, String name})>? _info;
  bool _busy = false;
  String? _error;

  static const _purple = Color(0xFF6B21A8);

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  void _loadInfo() {
    _info = ref.read(schoolRepositoryProvider).teacherCardInfo(widget.token);
  }

  @override
  void dispose() {
    _pin.dispose();
    _pinRepeat.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool firstPin}) async {
    final pin = _pin.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'Die PIN hat 4 bis 6 Ziffern.');
      return;
    }
    if (firstPin && pin != _pinRepeat.text) {
      setState(() => _error = 'Die beiden PINs sind nicht gleich.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final ok = await ref
          .read(schoolRepositoryProvider)
          .signInWithTeacherCard(widget.token, pin, firstPin: firstPin);
      if (ok) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SchoolRootScreen()),
          (_) => false,
        );
        return;
      }
      error = 'Die PIN stimmt nicht.';
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        final seconds =
            (e.details as Map?)?['retryAfterSeconds'] as int? ?? 900;
        final minutes = (seconds / 60).ceil();
        error = 'Zu viele falsche Versuche. Die Karte ist für $minutes '
            '${minutes == 1 ? 'Minute' : 'Minuten'} gesperrt.';
      } else if (e.code == 'already-exists') {
        // Ein anderes Gerät hat die PIN gerade festgelegt
        setState(_loadInfo);
        error = e.message;
      } else {
        error = schoolErrorText(e);
      }
    } catch (e) {
      error = schoolErrorText(e);
    }
    if (!mounted) return;
    _pin.clear();
    _pinRepeat.clear();
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Lerndex für Lehrkräfte'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: user != null
                  ? _signedIn(user.email ?? 'ein anderes Konto')
                  : FutureBuilder<({bool pinSet, String name})>(
                      future: _info,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return _message(schoolErrorText(snap.error!));
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return _pinForm(snap.data!);
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Auf dem Gerät ist noch jemand anderes angemeldet.
  Widget _signedIn(String email) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('🧑‍🏫', style: TextStyle(fontSize: 52), textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text(
        'Auf diesem Gerät ist gerade $email angemeldet. Zum Anmelden mit '
        'Ihrer Lehrer-Karte melden wir es zuerst ab.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[800], fontSize: 15),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                await signOutAccount(ref);
                if (mounted) setState(() => _busy = false);
              },
        style: FilledButton.styleFrom(
          backgroundColor: _purple,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text('Abmelden und mit Karte anmelden'),
      ),
    ],
  );

  Widget _message(String text) => Column(
    children: [
      const Text('🔒', style: TextStyle(fontSize: 52)),
      const SizedBox(height: 12),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
    ],
  );

  Widget _pinForm(({bool pinSet, String name}) info) {
    final firstPin = !info.pinSet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('🧑‍🏫', style: TextStyle(fontSize: 52), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          info.name.isEmpty ? 'Willkommen' : 'Hallo ${info.name}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          firstPin
              ? 'Legen Sie jetzt Ihre persönliche PIN fest (4 bis 6 Ziffern). '
                    'Danach melden Sie sich immer mit Karte und PIN an. Die '
                    'Karte allein reicht nicht.'
              : 'Bitte geben Sie Ihre PIN ein.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[800], fontSize: 15),
        ),
        const SizedBox(height: 20),
        _pinField(_pin, firstPin ? 'Neue PIN' : 'PIN', autofocus: true,
            onSubmitted: firstPin ? null : () => _submit(firstPin: false)),
        if (firstPin) ...[
          const SizedBox(height: 12),
          _pinField(_pinRepeat, 'PIN wiederholen',
              onSubmitted: () => _submit(firstPin: true)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : () => _submit(firstPin: firstPin),
          style: FilledButton.styleFrom(
            backgroundColor: _purple,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(firstPin ? 'PIN festlegen und anmelden' : 'Anmelden'),
        ),
        const SizedBox(height: 16),
        Text(
          'PIN vergessen? Die Schulleitung kann Ihnen eine neue Karte ausstellen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _pinField(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: !_busy,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, letterSpacing: 8),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
    );
  }
}
