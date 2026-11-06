import 'package:flutter/widgets.dart';

/// Gibt Controller frei, sobald das Widget (z.B. ein Dialog) wirklich aus dem
/// Baum verschwindet – erst nach der Schließen-Animation. Direkt nach
/// `await showDialog` freigegeben, würden die Textfelder während der
/// Animation noch auf freigegebene Controller zugreifen.
class DisposeControllers extends StatefulWidget {
  const DisposeControllers({
    super.key,
    required this.controllers,
    required this.child,
  });

  final List<ChangeNotifier> controllers;
  final Widget child;

  @override
  State<DisposeControllers> createState() => _DisposeControllersState();
}

class _DisposeControllersState extends State<DisposeControllers> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
