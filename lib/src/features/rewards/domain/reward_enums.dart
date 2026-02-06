/// Belohnungs-Status
enum RewardStatus {
  pending,   // Wartet auf Trigger
  approved,  // Freigeschaltet, kann eingelöst werden
  claimed,   // Bereits eingelöst
}

/// Belohnungs-Typ
enum RewardType {
  system,  // Automatische System-Belohnung
  parent,  // Von Eltern erstellt
}

/// Belohnungs-Trigger (Auslöser)
enum RewardTrigger {
  level,        // Bei bestimmtem Level
  xp,           // Bei bestimmten XP
  stars,        // Bei bestimmten Sternen
  streak,       // Bei Streak-Tagen
  perfectQuiz,  // Bei perfektem Quiz (10/10)
  quizCount,    // Bei X abgeschlossenen Quizzen
  manual,       // Manuell von Eltern (kein Auto-Trigger)
}

/// Extension für String-Konvertierung
extension RewardStatusExtension on RewardStatus {
  String toFirestore() {
    switch (this) {
      case RewardStatus.pending:
        return 'pending';
      case RewardStatus.approved:
        return 'approved';
      case RewardStatus.claimed:
        return 'claimed';
    }
  }

  static RewardStatus fromFirestore(String value) {
    switch (value) {
      case 'pending':
        return RewardStatus.pending;
      case 'approved':
        return RewardStatus.approved;
      case 'claimed':
        return RewardStatus.claimed;
      default:
        return RewardStatus.pending;
    }
  }
}

extension RewardTypeExtension on RewardType {
  String toFirestore() {
    switch (this) {
      case RewardType.system:
        return 'system';
      case RewardType.parent:
        return 'parent';
    }
  }

  static RewardType fromFirestore(String value) {
    switch (value) {
      case 'system':
        return RewardType.system;
      case 'parent':
        return RewardType.parent;
      default:
        return RewardType.parent;
    }
  }
}

extension RewardTriggerExtension on RewardTrigger {
  String toFirestore() {
    switch (this) {
      case RewardTrigger.level:
        return 'level';
      case RewardTrigger.xp:
        return 'xp';
      case RewardTrigger.stars:
        return 'stars';
      case RewardTrigger.streak:
        return 'streak';
      case RewardTrigger.perfectQuiz:
        return 'perfect_quiz';
      case RewardTrigger.quizCount:
        return 'quiz_count';
      case RewardTrigger.manual:
        return 'manual';
    }
  }

  static RewardTrigger fromFirestore(String value) {
    switch (value) {
      case 'level':
        return RewardTrigger.level;
      case 'xp':
        return RewardTrigger.xp;
      case 'stars':
        return RewardTrigger.stars;
      case 'streak':
        return RewardTrigger.streak;
      case 'perfect_quiz':
        return RewardTrigger.perfectQuiz;
      case 'quiz_count':
        return RewardTrigger.quizCount;
      case 'manual':
        return RewardTrigger.manual;
      default:
        return RewardTrigger.manual;
    }
  }

  String get displayName {
    switch (this) {
      case RewardTrigger.level:
        return 'Level erreichen';
      case RewardTrigger.xp:
        return 'XP erreichen';
      case RewardTrigger.stars:
        return 'Sterne sammeln';
      case RewardTrigger.streak:
        return 'Lern-Streak';
      case RewardTrigger.perfectQuiz:
        return 'Perfektes Quiz';
      case RewardTrigger.quizCount:
        return 'Anzahl Quizze';
      case RewardTrigger.manual:
        return 'Manuell';
    }
  }
}