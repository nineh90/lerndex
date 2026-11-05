import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'offline_write.dart';

/// ⏱️ LERNZEIT-TRACKER
///
/// Erfasst NUR echte Lernzeit:
/// ✅ Quiz-Spielen
/// ✅ KI-Tutor-Nutzung
/// ❌ Dashboard-Browsing
/// ❌ Einstellungen
/// ❌ App im Hintergrund (Lebenszyklus `paused`/`hidden`/`detached`)
/// ❌ Leerlauf: nach [idleTimeout] ohne Berührung/Taste wird nicht mehr
///    gezählt, bis das Kind wieder tippt
///
/// Schreibt jede Minute aktiver Lernzeit einen Heartbeat → Eltern sehen den
/// LIVE-Status. Im Hintergrund und im Leerlauf gibt es keinen Heartbeat, die
/// Eltern-Ansicht geht dann nach ein paar Minuten von „LIVE“ wieder aus.
///
/// Optionaler `subject`-Parameter — bei `saveTime()` wird die Sekunden-Summe
/// zusätzlich pro Fach in `learning_stats/{date}.subjects.{subject}` abgelegt.
/// Die Eltern-Statistik liest das aus für die Fächer-Übersicht.
///
/// `firstLearningDate` wird beim allerersten Speichern gesetzt, damit die
/// Durchschnittsberechnung pro Tag stimmt.
///
/// Speichern funktioniert offline: keine Transaktion, nur ein Batch mit
/// `FieldValue.increment`, der lokal sofort gilt und vom Firestore-SDK
/// nachgereicht wird, sobald das Gerät wieder online ist.
class LearningTimeTracker with WidgetsBindingObserver {
  final String userId;
  final String childId;

  /// Optionales Fach (z.B. "Mathe", "Deutsch", "Zahlen", "Buchstaben",
  /// "Farben & Formen", "KI-Tutor"). Wird in den Tages-Stats aufgeschlüsselt.
  final String? subject;

  /// Ohne Eingabe so lange gilt das Kind noch als aktiv.
  static const Duration idleTimeout = Duration(minutes: 3);

  /// Abstand der Heartbeats (Eltern-Dashboard zeigt LIVE bei < 5 Min.).
  static const Duration heartbeatInterval = Duration(seconds: 60);

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;

  /// Auf App-Lebenszyklus, Berührungen und Tasten hören (aus in Unit-Tests).
  final bool listenToApp;

  Timer? _timer;
  int _secondsTracked = 0;
  bool _isTracking = false;
  bool _inBackground = false;
  bool _listening = false;
  late DateTime _lastInput;
  DateTime? _lastHeartbeat;

  LearningTimeTracker({
    required this.userId,
    required this.childId,
    this.subject,
    FirebaseFirestore? firestore,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting this.listenToApp = true,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _now = clock ?? DateTime.now {
    _lastInput = _now();
  }

  DocumentReference<Map<String, dynamic>> get _childRef => _firestore
      .collection('users')
      .doc(userId)
      .collection('children')
      .doc(childId);

  /// Startet Zeit-Tracking
  void startTracking() {
    if (_isTracking) return;

    debugPrint(
      '⏱️ Lernzeit-Tracking gestartet${subject != null ? ' ($subject)' : ''}',
    );
    _isTracking = true;
    _lastInput = _now();
    _attachListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());

    // Sofort beim Start einen Heartbeat schreiben
    _writeHeartbeat();
  }

  /// Stoppt Zeit-Tracking
  void stopTracking() {
    if (!_isTracking) return;

    debugPrint('⏹️ Lernzeit-Tracking gestoppt bei $_secondsTracked Sekunden');
    _isTracking = false;
    _timer?.cancel();
    _timer = null;
    _detachListeners();
  }

  /// Eine Sekunde ist vergangen (Timer). Zählt nur, wenn das Kind gerade
  /// wirklich dabei ist.
  @visibleForTesting
  void tick() {
    if (!isCounting) return;
    _secondsTracked++;

    final last = _lastHeartbeat;
    if (last == null || _now().difference(last) >= heartbeatInterval) {
      _writeHeartbeat();
    }
  }

  /// Das Kind hat etwas getan (Tippen, Taste, Texteingabe). Global werden
  /// Berührungen und Tasten schon erkannt; Bildschirme mit langer
  /// Texteingabe können das zusätzlich aufrufen.
  void markActivity() {
    _lastInput = _now();
  }

  /// Seit [idleTimeout] keine Eingabe mehr.
  bool get isIdle => _now().difference(_lastInput) >= idleTimeout;

  /// Wird gerade Lernzeit gezählt?
  bool get isCounting => _isTracking && !_inBackground && !isIdle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_inBackground) {
          _inBackground = false;
          _lastInput = _now();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (!_inBackground) {
          _inBackground = true;
          // Im Hintergrund kann das System die App jederzeit beenden –
          // bisherige Lernzeit gleich sichern (best effort).
          if (_isTracking && _secondsTracked > 0) {
            unawaited(
              saveTime().catchError((Object e) {
                debugPrint('⚠️ Lernzeit beim Wechsel in den Hintergrund: $e');
              }),
            );
          }
        }
      case AppLifecycleState.inactive:
        // Kurz (Benachrichtigungen, Systemdialog) – weiterzählen.
        break;
    }
  }

  /// Speichert die getrackte Zeit zu Firebase.
  ///
  /// Ein einziger Batch: Kind-Dokument (`totalLearningSeconds`, beim ersten
  /// Mal `firstLearningDate`) und Tages-Statistik inkl. Fach-Aufschlüsselung.
  /// Wartet höchstens kurz auf den Server – offline wird der Batch lokal
  /// übernommen und später übertragen.
  Future<void> saveTime() async {
    final seconds = takeUnsavedSeconds();
    if (seconds == 0) return;

    try {
      debugPrint('💾 Speichere $seconds Sekunden Lernzeit...');

      final setFirst = await needsFirstLearningDate(_childRef);
      final batch = _firestore.batch();
      batch.set(
        _childRef,
        childTimeFields(seconds, setFirstLearningDate: setFirst),
        SetOptions(merge: true),
      );
      addDailyStatsToBatch(batch, seconds);

      await commitOfflineTolerant(
        batch,
        // Erst nach dem Warten abgelehnt (z.B. Rechte): Sekunden nicht
        // verlieren, beim nächsten Speichern noch einmal versuchen.
        onLateError: (_) => restoreSeconds(seconds),
      );

      debugPrint('✅ Lernzeit gespeichert: ${_formatTime(seconds)}');
    } catch (e) {
      restoreSeconds(seconds);
      debugPrint('❌ Fehler beim Speichern: $e');
      rethrow;
    }
  }

  /// Nimmt die bisher gezählten, noch nicht gespeicherten Sekunden heraus
  /// (der Timer zählt danach ab 0 weiter). Für Aufrufer, die die Lernzeit
  /// selbst in einen Batch schreiben (Quiz-Abschluss).
  int takeUnsavedSeconds() {
    final seconds = _secondsTracked;
    _secondsTracked = 0;
    return seconds;
  }

  /// Gibt Sekunden zurück, deren Speichern fehlgeschlagen ist.
  void restoreSeconds(int seconds) {
    if (seconds > 0) _secondsTracked += seconds;
  }

  /// Felder fürs Kind-Dokument. `lastLearningDate` setzt nur der Streak –
  /// sonst würde der Streak „heute schon gelernt“ erkennen und nie auf 1
  /// springen.
  static Map<String, dynamic> childTimeFields(
    int seconds, {
    required bool setFirstLearningDate,
  }) => {
    'totalLearningSeconds': FieldValue.increment(seconds),
    if (setFirstLearningDate) 'firstLearningDate': FieldValue.serverTimestamp(),
  };

  /// Trägt die Tages-Statistik (`learning_stats/{JJJJ-MM-TT}`) als EIN
  /// `set(merge)` in [batch] ein. Die Fach-Aufschlüsselung steht als
  /// verschachtelte Map drin: Merge führt verschachtelte Maps zusammen,
  /// andere Fächer desselben Tages bleiben erhalten.
  void addDailyStatsToBatch(WriteBatch batch, int seconds) {
    final now = _now();
    batch.set(
      _childRef.collection('learning_stats').doc(dateKey(now)),
      {
        'date': Timestamp.fromDate(now),
        'seconds': FieldValue.increment(seconds),
        if (subject != null && subject!.isNotEmpty)
          'subjects': {subject!: FieldValue.increment(seconds)},
      },
      SetOptions(merge: true),
    );
  }

  /// Muss `firstLearningDate` noch gesetzt werden? Liest zuerst aus dem
  /// lokalen Cache (das Dashboard hört auf das Kind-Dokument), sonst kurz
  /// vom Server. Unbekannt → nein (ein späteres Speichern holt es nach).
  static Future<bool> needsFirstLearningDate(
    DocumentReference<Map<String, dynamic>> childRef,
  ) async {
    Map<String, dynamic>? data;
    try {
      data = (await childRef.get(
        const GetOptions(source: Source.cache),
      )).data();
    } catch (_) {
      // Nicht im Cache
    }
    if (data == null) {
      try {
        data = (await childRef.get().timeout(
          const Duration(seconds: 4),
        )).data();
      } catch (_) {
        return false;
      }
    }
    return data != null && data['firstLearningDate'] == null;
  }

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get trackedSeconds => _secondsTracked;
  String get formattedTime => _formatTime(_secondsTracked);
  bool get isTracking => _isTracking;

  void dispose() {
    stopTracking();
  }

  // =========================================================================
  // PRIVATE HELPERS
  // =========================================================================

  void _attachListeners() {
    if (!listenToApp || _listening) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      HardwareKeyboard.instance.addHandler(_onKey);
      _listening = true;
    } catch (e) {
      // Ohne Flutter-Binding (reine Unit-Tests) – nur Timer.
      debugPrint('⚠️ Lernzeit: keine App-Ereignisse ($e)');
    }
  }

  void _detachListeners() {
    if (!_listening) return;
    _listening = false;
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerSignalEvent) {
      markActivity();
    }
  }

  bool _onKey(KeyEvent event) {
    markActivity();
    return false; // Taste nicht verbrauchen
  }

  /// Schreibt einen Heartbeat-Timestamp nach Firestore.
  /// Das Elterndashboard liest diesen Wert und zeigt LIVE an,
  /// wenn er weniger als 5 Minuten alt ist.
  void _writeHeartbeat() {
    _lastHeartbeat = _now();
    // Nicht abwarten: offline kommt die Bestätigung erst viel später.
    unawaited(
      _childRef
          .update({
            'lastActiveAt': FieldValue.serverTimestamp(),
            // Optional: aktuelles Fach mit-Heartbeaten, damit Eltern auch
            // im Live-Status sehen, was gelernt wird.
            if (subject != null) 'lastActiveSubject': subject,
          })
          .then((_) => debugPrint('💓 Heartbeat geschrieben'))
          .catchError((Object e) {
            // Heartbeat-Fehler sind nicht kritisch – kein rethrow
            debugPrint('⚠️ Heartbeat-Fehler (nicht kritisch): $e');
          }),
    );
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
