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
/// NEU: Schreibt alle 30s einen Heartbeat → Eltern sehen LIVE-Status

class LearningTimeTracker {
  final String userId;
  final String childId;
  final FirebaseFirestore _firestore;

  Timer? _timer;
  int _secondsTracked = 0;
  bool _isTracking = false;

  LearningTimeTracker({
    required this.userId,
    required this.childId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Startet Zeit-Tracking
  void startTracking() {
    if (_isTracking) return;

    debugPrint('⏱️ Lernzeit-Tracking gestartet');
    _isTracking = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _secondsTracked++;

      // Heartbeat alle 30 Sekunden → Eltern-Dashboard zeigt LIVE-Status
      if (_secondsTracked % 30 == 0) {
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

  /// Speichert die getrackte Zeit zu Firebase
  Future<void> saveTime() async {
    if (_secondsTracked == 0) return;

    try {
      debugPrint('💾 Speichere $_secondsTracked Sekunden Lernzeit...');

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .update({
            'totalLearningSeconds': FieldValue.increment(_secondsTracked),
            // lastLearningDate wird von updateStreak() gesetzt – nicht hier!
            // Würde updateStreak() sonst als 'heute bereits gelernt' erkennen
            // und den Streak beim ersten Mal nie auf 1 setzen.
          });

      // Tägliche Statistik
      await _saveDailyStats(_secondsTracked);

      debugPrint('✅ Lernzeit gespeichert: ${_formatTime(_secondsTracked)}');
      _secondsTracked = 0;
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
  /// Wird beim Start und dann alle 30 Sekunden aufgerufen.
  /// Das Elterndashboard liest diesen Wert und zeigt LIVE an,
  /// wenn er weniger als 5 Minuten alt ist.
  Future<void> _writeHeartbeat() async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .update({'lastActiveAt': FieldValue.serverTimestamp()});
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

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('learning_stats')
          .doc(dateKey)
          .set({
            'date': Timestamp.fromDate(now),
            'seconds': FieldValue.increment(seconds),
          }, SetOptions(merge: true));
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
