import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ============================================================================
// LETZTE EINGABE MERKEN
//
// Für die Abmeldung nach Inaktivität im Schulbereich (Browser am Klassen-PC):
// Jede Berührung, jeder Klick, jedes Scrollen und jeder Tastendruck in der
// App zählt als Aktivität. Erfasst wird das ganz oben im Widget-Baum
// (main.dart), damit auch aufgeschobene Seiten und Dialoge mitzählen.
// ============================================================================

class ActivityTracker {
  ActivityTracker._();

  static DateTime _lastActivity = DateTime.now();
  static bool _keyboardHooked = false;

  /// Zeitpunkt der letzten Eingabe.
  static DateTime get lastActivity => _lastActivity;

  /// Jetzt war jemand aktiv.
  static void touch([DateTime? now]) => _lastActivity = now ?? DateTime.now();

  /// Ist seit der letzten Eingabe mindestens [limit] vergangen?
  static bool idleFor(Duration limit, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(_lastActivity) >= limit;

  /// Tastatureingaben mitzählen (einmalig).
  static void listenToKeyboard() {
    if (_keyboardHooked) return;
    _keyboardHooked = true;
    HardwareKeyboard.instance.addHandler((_) {
      touch();
      return false; // Taste nicht verschlucken
    });
  }
}

/// Zählt Zeiger-Eingaben (Tippen, Klicken, Mausrad) als Aktivität, ohne sie
/// abzufangen.
class ActivityListener extends StatelessWidget {
  const ActivityListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    ActivityTracker.listenToKeyboard();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ActivityTracker.touch(),
      onPointerSignal: (_) => ActivityTracker.touch(),
      onPointerPanZoomStart: (_) => ActivityTracker.touch(),
      child: child,
    );
  }
}
