import 'package:cloud_firestore/cloud_firestore.dart';
import 'reward_enums.dart';

/// Erweitertes Belohnungs-Model mit Trigger-System
class RewardModel {
  final String id;
  final String childId;
  final String title;
  final String description;
  final RewardType type;
  final RewardTrigger trigger;

  // Trigger-Bedingungen (je nach trigger nur eine gesetzt)
  final int? requiredLevel;
  final int? requiredXP;
  final int? requiredStars;
  final int? requiredStreak;
  final int? requiredQuizCount;
  final String? avatarUnlockId; // Welcher Avatar freigeschaltet wird

  final RewardStatus status;
  final String reward; // Was das Kind bekommt

  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? claimedAt;
  final String createdBy; // 'system' oder userId
  final bool parentSeen;

  RewardModel({
    required this.id,
    required this.childId,
    required this.title,
    required this.description,
    required this.type,
    required this.trigger,
    this.requiredLevel,
    this.requiredXP,
    this.requiredStars,
    this.requiredStreak,
    this.requiredQuizCount,
    this.avatarUnlockId,
    required this.status,
    required this.reward,
    required this.createdAt,
    this.approvedAt,
    this.claimedAt,
    required this.createdBy,
    this.parentSeen = false,
  });

  /// Aus Firestore erstellen
  factory RewardModel.fromFirestore(Map<String, dynamic> data, String id) {
    return RewardModel(
      id: id,
      childId: data['childId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      type: RewardTypeExtension.fromFirestore(data['type'] ?? 'parent'),
      trigger: RewardTriggerExtension.fromFirestore(
        data['trigger'] ?? 'manual',
      ),
      requiredLevel: data['requiredLevel'],
      requiredXP: data['requiredXP'],
      requiredStars: data['requiredStars'],
      requiredStreak: data['requiredStreak'],
      requiredQuizCount: data['requiredQuizCount'],
      avatarUnlockId: data['avatarUnlockId'],
      status: RewardStatusExtension.fromFirestore(data['status'] ?? 'pending'),
      reward: data['reward'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      claimedAt: (data['claimedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? 'system',
      parentSeen: data['parentSeen'] == true,
    );
  }

  /// Zu Firestore konvertieren
  Map<String, dynamic> toFirestore() {
    return {
      'childId': childId,
      'title': title,
      'description': description,
      'type': type.toFirestore(),
      'trigger': trigger.toFirestore(),
      'requiredLevel': requiredLevel,
      'requiredXP': requiredXP,
      'requiredStars': requiredStars,
      'requiredStreak': requiredStreak,
      'requiredQuizCount': requiredQuizCount,
      if (avatarUnlockId != null) 'avatarUnlockId': avatarUnlockId,
      'status': status.toFirestore(),
      'reward': reward,
      'createdAt': Timestamp.fromDate(createdAt),
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'claimedAt': claimedAt != null ? Timestamp.fromDate(claimedAt!) : null,
      'createdBy': createdBy,
    };
  }

  /// Copy with für Updates
  RewardModel copyWith({
    String? id,
    String? childId,
    String? title,
    String? description,
    RewardType? type,
    RewardTrigger? trigger,
    int? requiredLevel,
    int? requiredXP,
    int? requiredStars,
    int? requiredStreak,
    int? requiredQuizCount,
    String? avatarUnlockId,
    RewardStatus? status,
    String? reward,
    DateTime? createdAt,
    DateTime? approvedAt,
    DateTime? claimedAt,
    String? createdBy,
    bool? parentSeen,
  }) {
    return RewardModel(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      trigger: trigger ?? this.trigger,
      requiredLevel: requiredLevel ?? this.requiredLevel,
      requiredXP: requiredXP ?? this.requiredXP,
      requiredStars: requiredStars ?? this.requiredStars,
      requiredStreak: requiredStreak ?? this.requiredStreak,
      requiredQuizCount: requiredQuizCount ?? this.requiredQuizCount,
      avatarUnlockId: avatarUnlockId ?? this.avatarUnlockId,
      status: status ?? this.status,
      reward: reward ?? this.reward,
      createdAt: createdAt ?? this.createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
      claimedAt: claimedAt ?? this.claimedAt,
      createdBy: createdBy ?? this.createdBy,
      parentSeen: parentSeen ?? this.parentSeen,
    );
  }

  /// Prüft ob Trigger-Bedingung erfüllt ist
  bool isTriggeredBy({
    required int currentLevel,
    required int currentXP,
    required int currentStars,
    required int currentStreak,
    required int currentQuizCount,
    bool isPerfectQuiz = false,
  }) {
    switch (trigger) {
      case RewardTrigger.level:
        return requiredLevel != null && currentLevel >= requiredLevel!;
      case RewardTrigger.xp:
        return requiredXP != null && currentXP >= requiredXP!;
      case RewardTrigger.stars:
        return requiredStars != null && currentStars >= requiredStars!;
      case RewardTrigger.streak:
        return requiredStreak != null && currentStreak >= requiredStreak!;
      case RewardTrigger.quizCount:
        return requiredQuizCount != null &&
            currentQuizCount >= requiredQuizCount!;
      case RewardTrigger.perfectQuiz:
        return isPerfectQuiz;
      case RewardTrigger.manual:
        return false;
      case RewardTrigger.avatarUnlock:
        return false; // Wird manuell von Eltern vergeben
    }
  }

  /// Gibt formatierte Bedingung zurück (für UI)
  String get conditionText {
    switch (trigger) {
      case RewardTrigger.level:
        return 'Level $requiredLevel erreichen';
      case RewardTrigger.xp:
        return '$requiredXP XP sammeln';
      case RewardTrigger.stars:
        return '$requiredStars ⭐ Sterne sammeln';
      case RewardTrigger.streak:
        return '$requiredStreak Tage am Stück lernen';
      case RewardTrigger.quizCount:
        return '$requiredQuizCount Quizze abschließen';
      case RewardTrigger.perfectQuiz:
        return 'Perfektes Quiz (10/10)';
      case RewardTrigger.manual:
        return 'Von Eltern freigegeben';
      case RewardTrigger.avatarUnlock:
        return '🎭 Avatar-Freischaltung';
    }
  }

  /// Status-Badge Farbe
  String get statusEmoji {
    switch (status) {
      case RewardStatus.pending:
        return '⏳';
      case RewardStatus.approved:
        return '🎁';
      case RewardStatus.claimed:
        return '✅';
    }
  }

  /// Ist einlösbar?
  bool get canClaim => status == RewardStatus.approved;
}
