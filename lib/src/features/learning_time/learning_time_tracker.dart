import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// ⏱️ LERNZEIT-TRACKER
///
/// Erfasst NUR echte Lernzeit:
/// ✅ Quiz-Spielen
/// ✅ KI-Tutor-Nutzung
/// ❌ Dashboard-Browsing
/// ❌ Einstellungen
///
/// Schreibt alle 60s einen Heartbeat → Eltern sehen LIVE-Status.
///
/// NEU: Optionaler `subject`-Parameter — bei `saveTime()` wird die Sekunden-
/// Summe zusätzlich pro Fach in `learning_stats/{date}.subjects.{subject}`
/// abgelegt. Die Eltern-Statistik liest das aus für die Fächer-Übersicht.
///
/// NEU: `firstLearningDate` wird beim allerersten saveTime() gesetzt, damit
/// die Durchschnittsberechnung pro Tag stimmt.

class LearningTimeTracker {
  final String userId;
  final String childId;

  /// Optionales Fach (z.B. "Mathe", "Deutsch", "Zahlen", "Buchstaben",
  /// "Farben & Formen", "Tutor"). Wird in den Tages-Stats aufgeschlüsselt.
  final String? subject;

  final FirebaseFirestore _firestore;

  Timer? _timer;
  int _secondsTracked = 0;
  bool _isTracking = false;

  LearningTimeTracker({
    required this.userId,
    required this.childId,
    this.subject,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Startet Zeit-Tracking
  void startTracking() {
    if (_isTracking) return;

    debugPrint(
      '⏱️ Lernzeit-Tracking gestartet${subject != null ? ' ($subject)' : ''}',
    );
    _isTracking = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _secondsTracked++;

      // Heartbeat alle 60 Sekunden → Eltern-Dashboard zeigt LIVE-Status.
      // (Das Dashboard wertet "LIVE" bei < 5 Min. Alter — 60s reicht dafür
      // locker und halbiert die Firestore-Writes gegenüber 30s.)
      if (_secondsTracked % 60 == 0) {
        _writeHeartbeat();
      }
    });

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
  }

  /// Speichert die getrackte Zeit zu Firebase.
  ///
  /// Setzt beim allerersten Aufruf `firstLearningDate` per `setIfMissing`-Logik
  /// (Transaction). Schreibt außerdem die Subject-Aufschlüsselung in die
  /// Tages-Statistik.
  Future<void> saveTime() async {
    if (_secondsTracked == 0) return;

    final secondsToSave = _secondsTracked;

    try {
      debugPrint('💾 Speichere $secondsToSave Sekunden Lernzeit...');

      final childRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId);

      // Transaktion: firstLearningDate nur setzen, wenn noch nicht vorhanden.
      // (Verhindert Race Conditions bei mehreren parallelen Quiz-Sessions.)
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(childRef);
        final data = snap.data();
        final updates = <String, dynamic>{
          'totalLearningSeconds': FieldValue.increment(secondsToSave),
          // lastLearningDate wird von updateStreak() gesetzt – nicht hier!
          // Würde updateStreak() sonst als 'heute bereits gelernt' erkennen
          // und den Streak beim ersten Mal nie auf 1 setzen.
        };

        if (data == null || data['firstLearningDate'] == null) {
          updates['firstLearningDate'] = FieldValue.serverTimestamp();
        }

        // set+merge statt update: schlägt nicht fehl, falls das Dokument
        // (z.B. durch Race mit einer Löschung) nicht mehr existiert.
        tx.set(childRef, updates, SetOptions(merge: true));
      });

      // Tägliche Statistik (inkl. Fach-Aufschlüsselung)
      await _saveDailyStats(secondsToSave);

      debugPrint('✅ Lernzeit gespeichert: ${_formatTime(secondsToSave)}');

      // ✅ FIX: Nicht hart auf 0 setzen, sondern nur die gespeicherten
      // Sekunden abziehen. Der Timer läuft während des async-Speicherns
      // weiter – ein hartes `= 0` würde die zwischenzeitlich getrackten
      // Sekunden verwerfen (Lernzeit-Verlust bei jedem Zwischenspeichern).
      _secondsTracked -= secondsToSave;
      if (_secondsTracked < 0) _secondsTracked = 0;
    } catch (e) {
      debugPrint('❌ Fehler beim Speichern: $e');
      rethrow;
    }
  }

  int get trackedSeconds => _secondsTracked;
  String get formattedTime => _formatTime(_secondsTracked);
  bool get isTracking => _isTracking;

  void dispose() {
    stopTracking();
  }

  // =========================================================================
  // PRIVATE HELPERS
  // =========================================================================

  /// Schreibt einen Heartbeat-Timestamp nach Firestore.
  /// Wird beim Start und dann alle 60 Sekunden aufgerufen.
  /// Das Elterndashboard liest diesen Wert und zeigt LIVE an,
  /// wenn er weniger als 5 Minuten alt ist.
  Future<void> _writeHeartbeat() async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .update({
            'lastActiveAt': FieldValue.serverTimestamp(),
            // Optional: aktuelles Fach mit-Heartbeaten, damit Eltern auch
            // im Live-Status sehen, was gelernt wird.
            if (subject != null) 'lastActiveSubject': subject,
          });
      debugPrint('💓 Heartbeat geschrieben');
    } catch (e) {
      // Heartbeat-Fehler sind nicht kritisch – kein rethrow
      debugPrint('⚠️ Heartbeat-Fehler (nicht kritisch): $e');
    }
  }

  Future<void> _saveDailyStats(int seconds) async {
    try {
      final now = DateTime.now();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('learning_stats')
          .doc(dateKey);

      // WICHTIG: `set(merge: true)` parst dotted-keys NICHT als Map-Pfade —
      // `subjects.Mathe` würde als Top-Level-Feld mit Punkt im Namen landen.
      // Daher 2-Phasen:
      //   1) Sicherstellen, dass Dokument existiert (date + seconds-Inkrement)
      //   2) Per UPDATE die dotted-field-Pfade schreiben (parst korrekt
      //      zu verschachteltem Map subjects.{Fach})

      // Phase 1: Existenz sicherstellen + Top-Level-Felder
      await docRef.set({
        'date': Timestamp.fromDate(now),
        'seconds': FieldValue.increment(seconds),
      }, SetOptions(merge: true));

      // Phase 2: Subject-Aufschlüsselung via update() — hier wird die
      // Dot-Notation als Pfad geparst und ergibt verschachteltes Map.
      if (subject != null && subject!.isNotEmpty) {
        await docRef.update({
          'subjects.$subject': FieldValue.increment(seconds),
        });
      }
    } catch (e) {
      debugPrint('⚠️ Tages-Stats Fehler: $e');
    }
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
