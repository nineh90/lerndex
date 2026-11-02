import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../parent_dashboard/data/pin_repository.dart';
import '../../data/auth_repository.dart';
import '../../data/child_device_repository.dart';
import '../active_child_provider.dart';
import '../login_screen.dart';

/// Abmelden auf einem Kinder- oder Schülergerät.
///
/// Schul-Tablet: ohne PIN, damit das nächste Kind seine Karte scannen kann.
/// Zu Hause (gekoppeltes Kindergerät): nur mit dem Eltern-PIN, den der Server
/// prüft (leaveChildDevice). Das Kind selbst kommt so nicht heraus.
class DeviceLogoutButton extends ConsumerWidget {
  const DeviceLogoutButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSchool = ref.watch(isSchoolDeviceProvider);
    return IconButton(
      tooltip: isSchool ? 'Abmelden' : 'Eltern: Gerät abmelden',
      icon: Icon(
        isSchool ? Icons.logout_rounded : Icons.lock_outline_rounded,
        color: color,
      ),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => isSchool
              ? const _SchoolLogoutDialog()
              : const _ParentPinLogoutDialog(),
        );
        if (ok != true || !context.mounted) return;
        // Navigator vorher holen: Abmelden baut das Dashboard um, danach
        // gäbe es diesen Knopf (und seinen context) nicht mehr.
        final navigator = Navigator.of(context);
        final activeChild = ref.read(activeChildProvider.notifier);
        await ref.read(authRepositoryProvider).signOut();
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        activeChild.deselect();
      },
    );
  }
}

class _SchoolLogoutDialog extends StatelessWidget {
  const _SchoolLogoutDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abmelden?'),
      content: const Text('Danach kann das nächste Kind seine Karte scannen.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Abmelden'),
        ),
      ],
    );
  }
}

/// Eltern-PIN eingeben; bei richtigem PIN trägt der Server das Gerät aus und
/// der Dialog gibt true zurück.
class _ParentPinLogoutDialog extends ConsumerStatefulWidget {
  const _ParentPinLogoutDialog();

  @override
  ConsumerState<_ParentPinLogoutDialog> createState() =>
      _ParentPinLogoutDialogState();
}

class _ParentPinLogoutDialogState
    extends ConsumerState<_ParentPinLogoutDialog> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pin.text.length < 4) {
      setState(() => _error = 'PIN zu kurz');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final ok =
          await ref.read(childDeviceRepositoryProvider).leaveDevice(_pin.text);
      if (ok) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      error = 'Falscher PIN';
    } on PinLockedException catch (e) {
      final minutes = (e.remaining.inSeconds / 60).ceil();
      error = 'Zu viele Versuche. Bitte in $minutes '
          '${minutes == 1 ? 'Minute' : 'Minuten'} nochmal.';
    } on PairingException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Das hat nicht geklappt. Bitte gleich nochmal versuchen.';
    }
    if (!mounted) return;
    _pin.clear();
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gerät abmelden'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nur für Eltern: Mit deinem Eltern-PIN meldest du dieses Gerät '
            'ab. Danach kannst du dich hier selbst anmelden oder das Gerät '
            'neu koppeln.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            decoration: InputDecoration(
              labelText: 'Eltern-PIN',
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Abmelden'),
        ),
      ],
    );
  }
}
