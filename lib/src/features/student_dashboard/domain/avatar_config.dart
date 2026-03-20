import 'package:flutter/material.dart';

/// Konfiguration für einen Avatar
class AvatarConfig {
  final String id;
  final String label;
  final int requiredLevel; // 0 wenn isRewardUnlock = true
  final Color color;
  final String rarityLabel;
  final bool isRewardUnlock; // true = wird über Belohnung freigeschaltet
  // Für spätere Payment-Integration:
  // final bool requiresPayment;
  // final String? productId;

  const AvatarConfig({
    required this.id,
    required this.label,
    required this.requiredLevel,
    required this.color,
    required this.rarityLabel,
    this.isRewardUnlock = false,
  });
}

const List<AvatarConfig> kAvatars = [
  // ── STANDARD-AVATARE (Level-basiert) ──────────────────────────────────────
  AvatarConfig(
    id: 'avatar-common',
    label: 'Common',
    requiredLevel: 1,
    color: Color(0xFF78909C),
    rarityLabel: '⬜ Common',
  ),
  AvatarConfig(
    id: 'avatar-common-1',
    label: 'Common',
    requiredLevel: 1,
    color: Color(0xFF78909C),
    rarityLabel: '⬜ Common',
  ),
  AvatarConfig(
    id: 'avatar-uncommon',
    label: 'Uncommon',
    requiredLevel: 5,
    color: Color(0xFF43A047),
    rarityLabel: '🟩 Uncommon',
  ),
  AvatarConfig(
    id: 'avatar-uncommon-1',
    label: 'Uncommon',
    requiredLevel: 5,
    color: Color(0xFF43A047),
    rarityLabel: '🟩 Uncommon',
  ),
  AvatarConfig(
    id: 'avatar-rare',
    label: 'Rare',
    requiredLevel: 10,
    color: Color(0xFF1E88E5),
    rarityLabel: '🟦 Rare',
  ),
  AvatarConfig(
    id: 'avatar-epic',
    label: 'Epic',
    requiredLevel: 25,
    color: Color(0xFF8E24AA),
    rarityLabel: '🟪 Epic',
  ),
  AvatarConfig(
    id: 'avatar-legendary',
    label: 'Legendary',
    requiredLevel: 50,
    color: Color(0xFFFF8F00),
    rarityLabel: '🟨 Legendary',
  ),
  AvatarConfig(
    id: 'avatar-legendary-1',
    label: 'Legendary',
    requiredLevel: 50,
    color: Color(0xFFFF8F00),
    rarityLabel: '🟨 Legendary',
  ),
  // ── ELTERN-GIFT-AVATARE ──────────────────────────────────────────────────
  // Nur diese Avatare (id startet mit "avatar-gift") erscheinen im
  // Belohnungs-Dialog der Eltern. Neue hinzufügen als avatar-gift-1,
  // avatar-gift-2 usw. – Bild muss unter assets/images/ liegen.
  AvatarConfig(
    id: 'avatar-gift',
    label: 'Geschenk',
    requiredLevel: 0,
    color: Color(0xFFE53935),
    rarityLabel: '🎁 Geschenk',
    isRewardUnlock: true,
  ),

  AvatarConfig(
    id: 'avatar-gift-1',
    label: 'Geschenk',
    requiredLevel: 0,
    color: Color(0xFFE53935),
    rarityLabel: '🎁 Geschenk',
    isRewardUnlock: true,
  ),

  AvatarConfig(
    id: 'avatar-gift-2',
    label: 'Geschenk',
    requiredLevel: 0,
    color: Color(0xFFE53935),
    rarityLabel: '🎁 Geschenk',
    isRewardUnlock: true,
  ),

  // ── STREAK-EXKLUSIVE AVATARE ───────────────────────────────────────────────
  // Freischaltbar nur durch Streak-Meilensteine (14 / 28 / 42 Tage)
  AvatarConfig(
    id: 'avatar-streak-uncommon',
    label: 'Streak 14',
    requiredLevel: 0,
    color: Color(0xFF00BCD4),
    rarityLabel: '🔥 Streak-Rare',
    isRewardUnlock: true,
  ),
  AvatarConfig(
    id: 'avatar-streak-epic',
    label: 'Streak 28',
    requiredLevel: 0,
    color: Color(0xFF7C4DFF),
    rarityLabel: '⚡ Streak-Epic',
    isRewardUnlock: true,
  ),
  AvatarConfig(
    id: 'avatar-streak-legendary',
    label: 'Streak 42',
    requiredLevel: 0,
    color: Color(0xFFFF6D00),
    rarityLabel: '👑 Streak-Legend',
    isRewardUnlock: true,
  ),

  // ── ACHIEVEMENT-AVATARE ────────────────────────────────────────────────────
  // Freischaltbar nur durch besondere In-App-Leistungen
  AvatarConfig(
    id: 'avatar-champion',
    label: 'Champion',
    requiredLevel: 0,
    color: Color(0xFFFFD600), // Leuchtendes Gold
    rarityLabel: '🏆 Champion',
    isRewardUnlock: true,
  ),
  AvatarConfig(
    id: 'avatar-legend',
    label: 'Legende',
    requiredLevel: 0,
    color: Color(0xFFAA00FF), // Tiefes Violett
    rarityLabel: '💎 Legende',
    isRewardUnlock: true,
  ),
  AvatarConfig(
    id: 'avatar-xp-5k',
    label: 'XP-Titan',
    requiredLevel: 0,
    color: Color(0xFF00E5FF), // Cyan-Electric
    rarityLabel: '⚡ XP-Titan',
    isRewardUnlock: true,
  ),
  AvatarConfig(
    id: 'avatar-quiz-master',
    label: 'Quiz-Meister',
    requiredLevel: 0,
    color: Color(0xFF76FF03), // Neon-Grün
    rarityLabel: '🎯 Quiz-Meister',
    isRewardUnlock: true,
  ),
];
