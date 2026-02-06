import 'package:cloud_firestore/cloud_firestore.dart';

/// Repräsentiert eine Belohnung
class Reward {
  final String id;
  final String childId;           // Für welches Kind
  final String title;             // z.B. "10€ Taschengeld"
  final String description;       // z.B. "Für fleißiges Lernen"
  final String icon;              // Emoji oder Icon-Name
  final String trigger;           // Was löst die Belohnung aus
  final int triggerValue;         // Wert des Triggers (z.B. 5 für Level 5)
  final bool isUnlocked;          // Wurde bereits verdient?
  final bool isRedeemed;          // Wurde bereits eingelöst?
  final DateTime? unlockedAt;     // Wann wurde sie freigeschaltet?
  final DateTime? redeemedAt;     // Wann wurde sie eingelöst?
  final DateTime createdAt;       // Wann wurde sie erstellt?

  Reward({
    required this.id,
    required this.childId,
    required this.title,
    required this.description,
    required this.icon,
    required this.trigger,
    required this.triggerValue,
    this.isUnlocked = false,
    this.isRedeemed = false,
    this.unlockedAt,
    this.redeemedAt,
    required this.createdAt,
  });

  /// Erstellt Reward aus Firestore-Daten
  factory Reward.fromMap(Map<String, dynamic> data, String id) {
    return Reward(
      id: id,
      childId: data['childId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '🎁',
      trigger: data['trigger'] ?? 'level',
      triggerValue: data['triggerValue'] ?? 1,
      isUnlocked: data['isUnlocked'] ?? false,
      isRedeemed: data['isRedeemed'] ?? false,
      unlockedAt: data['unlockedAt'] != null
          ? (data['unlockedAt'] as Timestamp).toDate()
          : null,
      redeemedAt: data['redeemedAt'] != null
          ? (data['redeemedAt'] as Timestamp).toDate()
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Konvertiert zu Firestore-Map
  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'title': title,
      'description': description,
      'icon': icon,
      'trigger': trigger,
      'triggerValue': triggerValue,
      'isUnlocked': isUnlocked,
      'isRedeemed': isRedeemed,
      'unlockedAt': unlockedAt,
      'redeemedAt': redeemedAt,
      'createdAt': createdAt,
    };
  }

  /// Erstellt eine Kopie mit geänderten Werten
  Reward copyWith({
    String? id,
    String? childId,
    String? title,
    String? description,
    String? icon,
    String? trigger,
    int? triggerValue,
    bool? isUnlocked,
    bool? isRedeemed,
    DateTime? unlockedAt,
    DateTime? redeemedAt,
    DateTime? createdAt,
  }) {
    return Reward(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      trigger: trigger ?? this.trigger,
      triggerValue: triggerValue ?? this.triggerValue,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      isRedeemed: isRedeemed ?? this.isRedeemed,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      redeemedAt: redeemedAt ?? this.redeemedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Trigger-Typen für Belohnungen
class RewardTrigger {
  static const String level = 'level';           // Bei Level X erreicht
  static const String quizCount = 'quizCount';   // Nach X Quiz
  static const String stars = 'stars';           // Bei X Sternen
  static const String learningTime = 'learningTime'; // Nach X Minuten Lernzeit
  static const String streak = 'streak';         // Nach X Tagen Streak

  /// Gibt einen lesbaren Namen für den Trigger zurück
  static String getDisplayName(String trigger) {
    switch (trigger) {
      case level:
        return 'Level erreicht';
      case quizCount:
        return 'Quiz abgeschlossen';
      case stars:
        return 'Sterne gesammelt';
      case learningTime:
        return 'Lernzeit';
      case streak:
        return 'Tage-Streak';
      default:
        return 'Unbekannt';
    }
  }

  /// Gibt eine Beschreibung des Triggers zurück
  static String getDescription(String trigger, int value) {
    switch (trigger) {
      case level:
        return 'Bei Level $value';
      case quizCount:
        return 'Nach $value Quiz';
      case stars:
        return 'Bei $value Sternen';
      case learningTime:
        return 'Nach $value Minuten Lernzeit';
      case streak:
        return 'Nach $value Tagen in Folge';
      default:
        return '';
    }
  }
}

/// Standard-Belohnungen (Vorschläge für Eltern)
class DefaultRewards {
  static List<Map<String, dynamic>> get suggestions => [
    {
      'title': '10€ Taschengeld',
      'description': 'Extra Taschengeld für fleißiges Lernen',
      'icon': '💰',
      'trigger': RewardTrigger.level,
      'triggerValue': 5,
    },
    {
      'title': 'Kinobesuch',
      'description': 'Ein Film deiner Wahl im Kino',
      'icon': '🎬',
      'trigger': RewardTrigger.quizCount,
      'triggerValue': 20,
    },
    {
      'title': 'Lieblingsessen',
      'description': 'Du darfst das Abendessen aussuchen',
      'icon': '🍕',
      'trigger': RewardTrigger.stars,
      'triggerValue': 100,
    },
    {
      'title': '30 Min länger aufbleiben',
      'description': 'An einem Tag deiner Wahl',
      'icon': '🌙',
      'trigger': RewardTrigger.learningTime,
      'triggerValue': 60, // 60 Minuten
    },
    {
      'title': 'Spielzeug (bis 20€)',
      'description': 'Ein Spielzeug deiner Wahl',
      'icon': '🎮',
      'trigger': RewardTrigger.level,
      'triggerValue': 10,
    },
    {
      'title': 'Freund zum Übernachten einladen',
      'description': 'Ein Freund darf übernachten',
      'icon': '🏠',
      'trigger': RewardTrigger.streak,
      'triggerValue': 7,
    },
    {
      'title': 'Freizeitpark-Besuch',
      'description': 'Ein Tag im Freizeitpark',
      'icon': '🎢',
      'trigger': RewardTrigger.level,
      'triggerValue': 15,
    },
    {
      'title': 'Keine Hausarbeit',
      'description': 'Einen Tag frei von Hausarbeiten',
      'icon': '🧹',
      'trigger': RewardTrigger.quizCount,
      'triggerValue': 10,
    },
  ];
}