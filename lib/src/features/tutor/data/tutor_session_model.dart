import 'package:cloud_firestore/cloud_firestore.dart';

/// 💬 TUTOR SESSION MODEL
/// Repräsentiert eine zusammenhängende Tutor-Session
class TutorSession {
  final String id;
  final String childId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status; // 'active' | 'completed'
  final int messageCount;
  final int durationSeconds;
  final String? detectedTopic; // 'Mathematik', 'Deutsch', etc.
  final String? firstQuestion; // Erste Frage des Schülers

  // Zukünftig für Belohnungen
  final int? xpEarned;
  final int? starsEarned;

  const TutorSession({
    required this.id,
    required this.childId,
    required this.startedAt,
    this.endedAt,
    required this.status,
    this.messageCount = 0,
    this.durationSeconds = 0,
    this.detectedTopic,
    this.firstQuestion,
    this.xpEarned,
    this.starsEarned,
  });

  /// Erstellt Session aus Firestore
  factory TutorSession.fromFirestore(Map<String, dynamic> data, String id) {
    return TutorSession(
      id: id,
      childId: data['childId'] ?? '',
      startedAt: (data['startedAt'] as Timestamp).toDate(),
      endedAt: data['endedAt'] != null
          ? (data['endedAt'] as Timestamp).toDate()
          : null,
      status: data['status'] ?? 'active',
      messageCount: data['messageCount'] ?? 0,
      durationSeconds: data['durationSeconds'] ?? 0,
      detectedTopic: data['detectedTopic'],
      firstQuestion: data['firstQuestion'],
      xpEarned: data['xpEarned'],
      starsEarned: data['starsEarned'],
    );
  }

  /// Konvertiert zu Firestore Map
  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'startedAt': Timestamp.fromDate(startedAt),
      if (endedAt != null) 'endedAt': Timestamp.fromDate(endedAt!),
      'status': status,
      'messageCount': messageCount,
      'durationSeconds': durationSeconds,
      if (detectedTopic != null) 'detectedTopic': detectedTopic,
      if (firstQuestion != null) 'firstQuestion': firstQuestion,
      if (xpEarned != null) 'xpEarned': xpEarned,
      if (starsEarned != null) 'starsEarned': starsEarned,
    };
  }

  /// Kopie mit geänderten Werten
  TutorSession copyWith({
    String? id,
    String? childId,
    DateTime? startedAt,
    DateTime? endedAt,
    String? status,
    int? messageCount,
    int? durationSeconds,
    String? detectedTopic,
    String? firstQuestion,
    int? xpEarned,
    int? starsEarned,
  }) {
    return TutorSession(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      messageCount: messageCount ?? this.messageCount,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      detectedTopic: detectedTopic ?? this.detectedTopic,
      firstQuestion: firstQuestion ?? this.firstQuestion,
      xpEarned: xpEarned ?? this.xpEarned,
      starsEarned: starsEarned ?? this.starsEarned,
    );
  }

  /// Prüft ob Session aktiv ist
  bool get isActive => status == 'active';

  /// Prüft ob Session abgeschlossen ist
  bool get isCompleted => status == 'completed';

  /// Berechnet Dauer basierend auf Start/Ende
  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  /// Formatierte Dauer
  String get formattedDuration {
    final d = duration;
    if (d.inMinutes < 1) {
      return '< 1 Min';
    } else if (d.inMinutes < 60) {
      return '${d.inMinutes} Min';
    } else {
      final hours = d.inHours;
      final minutes = d.inMinutes % 60;
      return '${hours}h ${minutes}min';
    }
  }

  /// Erkenne Thema aus Text (Heuristik)
  static String detectTopic(String text) {
    final lower = text.toLowerCase();

    if (lower.contains('mathe') || lower.contains('rechnen') ||
        lower.contains('plus') || lower.contains('minus') ||
        lower.contains('mal') || lower.contains('geteilt') ||
        lower.contains('bruch') || lower.contains('prozent') ||
        lower.contains('gleichung') || lower.contains('wurzel')) {
      return 'Mathematik';
    }

    if (lower.contains('deutsch') || lower.contains('grammatik') ||
        lower.contains('rechtschreibung') || lower.contains('wort') ||
        lower.contains('satz') || lower.contains('adjektiv') ||
        lower.contains('verb') || lower.contains('nomen')) {
      return 'Deutsch';
    }

    if (lower.contains('englisch') || lower.contains('english') ||
        lower.contains('past') || lower.contains('present') ||
        lower.contains('future') || lower.contains('tense')) {
      return 'Englisch';
    }

    if (lower.contains('sachkunde') || lower.contains('natur') ||
        lower.contains('pflanzen') || lower.contains('tiere') ||
        lower.contains('wasser') || lower.contains('umwelt')) {
      return 'Sachkunde';
    }

    return 'Allgemein';
  }
}