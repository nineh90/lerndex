import 'package:flutter/material.dart';
import '../../auth/domain/child_model.dart';

// ============================================================================
// DYNAMISCHE FÄCHER-KONFIGURATION
// Basierend auf schoolType + grade des Kindes – einfach erweiterbar
// ============================================================================

class SubjectConfig {
  final String title;
  final String emoji;
  final IconData icon;
  final List<Color> gradientColors;
  final String subject; // Übergabewert an QuizScreen

  const SubjectConfig({
    required this.title,
    required this.emoji,
    required this.icon,
    required this.gradientColors,
    required this.subject,
  });
}

/// Gibt die passenden Fächer für ein Kind zurück
/// Basiert auf schoolType und grade aus ChildModel
List<SubjectConfig> getSubjectsForChild(ChildModel child) {
  final grade = child.grade;
  final schoolType = child.schoolType;

  // ── Grundschule (Klasse 1–4) ─────────────────────────────────────────────
  if (schoolType == 'Grundschule' || grade <= 4) {
    return const [
      SubjectConfig(
        title: 'Mathe',
        emoji: '🔢',
        icon: Icons.calculate_rounded,
        gradientColors: [Color(0xFF7E57C2), Color(0xFF512DA8)],
        subject: 'Mathe',
      ),
      SubjectConfig(
        title: 'Deutsch',
        emoji: '📖',
        icon: Icons.menu_book_rounded,
        gradientColors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
        subject: 'Deutsch',
      ),
      SubjectConfig(
        title: 'Englisch',
        emoji: '🌍',
        icon: Icons.language_rounded,
        gradientColors: [Color(0xFF1E88E5), Color(0xFF039BE5)],
        subject: 'Englisch',
      ),
      SubjectConfig(
        title: 'Sachkunde',
        emoji: '🌿',
        icon: Icons.wb_sunny_rounded,
        gradientColors: [Color(0xFF43A047), Color(0xFF7CB342)],
        subject: 'Sachkunde',
      ),
    ];
  }

  // ── Mittelstufe (Klasse 5–10) ─────────────────────────────────────────────
  if (grade <= 10) {
    return const [
      SubjectConfig(
        title: 'Mathe',
        emoji: '🔢',
        icon: Icons.calculate_rounded,
        gradientColors: [Color(0xFF7E57C2), Color(0xFF512DA8)],
        subject: 'Mathe',
      ),
      SubjectConfig(
        title: 'Deutsch',
        emoji: '✍️',
        icon: Icons.menu_book_rounded,
        gradientColors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
        subject: 'Deutsch',
      ),
      SubjectConfig(
        title: 'Englisch',
        emoji: '🌍',
        icon: Icons.language_rounded,
        gradientColors: [Color(0xFF1E88E5), Color(0xFF039BE5)],
        subject: 'Englisch',
      ),
      SubjectConfig(
        title: 'Biologie',
        emoji: '🧬',
        icon: Icons.biotech_rounded,
        gradientColors: [Color(0xFF26A69A), Color(0xFF00897B)],
        subject: 'Biologie',
      ),
      SubjectConfig(
        title: 'Chemie',
        emoji: '🧪',
        icon: Icons.science_rounded,
        gradientColors: [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
        subject: 'Chemie',
      ),
      SubjectConfig(
        title: 'Physik',
        emoji: '⚡',
        icon: Icons.bolt_rounded,
        gradientColors: [Color(0xFF5C6BC0), Color(0xFF512DA8)],
        subject: 'Physik',
      ),
      SubjectConfig(
        title: 'Geschichte',
        emoji: '🏛️',
        icon: Icons.account_balance_rounded,
        gradientColors: [Color(0xFF8D6E63), Color(0xFF546E7A)],
        subject: 'Geschichte',
      ),
    ];
  }

  // ── Oberstufe (Klasse 11–13) ──────────────────────────────────────────────
  return const [
    SubjectConfig(
      title: 'Mathe',
      emoji: '📐',
      icon: Icons.calculate_rounded,
      gradientColors: [Color(0xFF7E57C2), Color(0xFF512DA8)],
      subject: 'Mathe',
    ),
    SubjectConfig(
      title: 'Deutsch',
      emoji: '✍️',
      icon: Icons.menu_book_rounded,
      gradientColors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
      subject: 'Deutsch',
    ),
    SubjectConfig(
      title: 'Englisch',
      emoji: '🌍',
      icon: Icons.language_rounded,
      gradientColors: [Color(0xFF1E88E5), Color(0xFF039BE5)],
      subject: 'Englisch',
    ),
    SubjectConfig(
      title: 'Chemie',
      emoji: '🧪',
      icon: Icons.science_rounded,
      gradientColors: [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
      subject: 'Chemie',
    ),
    SubjectConfig(
      title: 'Physik',
      emoji: '⚡',
      icon: Icons.bolt_rounded,
      gradientColors: [Color(0xFF3949AB), Color(0xFF1A237E)],
      subject: 'Physik',
    ),
    SubjectConfig(
      title: 'Geschichte',
      emoji: '🏛️',
      icon: Icons.account_balance_rounded,
      gradientColors: [Color(0xFF8D6E63), Color(0xFF546E7A)],
      subject: 'Geschichte',
    ),
  ];
}
