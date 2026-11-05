import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// App Check für firebase_ai, das bei einem fehlenden Token nicht abbricht.
///
/// firebase_ai holt vor jeder KI-Anfrage ein App-Check-Token. Wirft das
/// (Play Integrity sagt nein, „Too many attempts“, kein Play Store auf dem
/// Gerät, Netzproblem), scheitert die ganze Anfrage, auch wenn App Check
/// nur beobachtet und Anfragen ohne Token noch durchlässt. So fiel beim Test
/// am 05.11.2026 jede KI-Funktion aus.
///
/// Hier wird ein fehlgeschlagenes Token zu `null`: firebase_ai schickt die
/// Anfrage dann ohne Token. Solange App Check auf „Monitoring“ steht, läuft
/// die KI weiter; sobald Google es erzwingt (21.01.2027), lehnt der Server
/// solche Anfragen ab, genauso wie vorher. Sicherheit geht also nicht
/// verloren, nur der unnötige Ausfall.
///
/// firebase_ai ruft nur [getToken] bzw. [getLimitedUseToken] auf, der Rest
/// wird durchgereicht.
class TolerantAppCheck implements FirebaseAppCheck {
  TolerantAppCheck(this._inner);

  final FirebaseAppCheck _inner;
  static bool _reported = false;

  @override
  FirebaseApp get app => _inner.app;

  @override
  set app(FirebaseApp value) => _inner.app = value;

  @override
  Future<String?> getToken([bool? forceRefresh]) async {
    try {
      return await _inner.getToken(forceRefresh);
    } catch (e, st) {
      _report(e, st);
      return null;
    }
  }

  @override
  Future<String> getLimitedUseToken() => _inner.getLimitedUseToken();

  @override
  Future<void> setTokenAutoRefreshEnabled(bool isTokenAutoRefreshEnabled) =>
      _inner.setTokenAutoRefreshEnabled(isTokenAutoRefreshEnabled);

  @override
  Stream<String?> get onTokenChange => _inner.onTokenChange;

  /// Einmal pro App-Start an Crashlytics, damit wir sehen, wie oft Geräte
  /// kein Token bekommen (wichtig vor dem Erzwingen).
  static void _report(Object e, StackTrace st) {
    debugPrint('⚠️ App Check ohne Token, KI-Anfrage geht ohne raus: $e');
    if (_reported || kIsWeb) return;
    _reported = true;
    FirebaseCrashlytics.instance.recordError(
      e,
      st,
      reason: 'App Check: kein Token für KI-Anfrage',
      fatal: false,
    );
  }

  // activate() & Co. braucht firebase_ai nicht
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
