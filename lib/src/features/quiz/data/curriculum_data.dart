// ============================================================================
// 📚 CURRICULUM DATA — Lehrplandaten für alle Schulformen & Klassenstufen
//
// Basiert auf:
//   - KMK-Bildungsstandards (ESA/MSA/Abitur) 2022–2024
//   - IQB-Kompetenzstufenmodelle (5 Stufen)
//   - LehrplanPLUS Bayern, Kernlehrpläne NRW, Rahmenlehrplan Berlin-Brandenburg
//
// Struktur:
//   CurriculumData.getTopics(schulform, klasse, fach) → Themen + Operatoren
//   CurriculumData.getDifficultyProfile(schulform, level) → Schwierigkeitsprofil
//   CurriculumData.getCompetencyLevel(level) → IQB-Kompetenzstufe
// ============================================================================

/// IQB-Kompetenzstufen (empirisch validiertes 5-Stufen-Modell)
///
/// Die Stufen beschreiben, WAS ein Schüler auf diesem Niveau können muss.
/// Sie sind abschlussübergreifend — die Labels verschieben sich je nach
/// Zielabschluss (z.B. Stufe II = Regelstandard HSA, Mindeststandard MSA).
enum CompetencyLevel {
  /// Stufe I: Grundlegende Bildungsziele nicht erreicht — dringender Förderbedarf
  /// Reproduzieren einfachster Fakten in stark geübten Kontexten
  belowMinimum,

  /// Stufe II: Mindeststandard erreicht — einfache Anwendungen in klarem Kontext
  /// Regelstandard für HSA / Mindeststandard für MSA
  minimum,

  /// Stufe III: Regelstandard — flexibles Anwenden in vertrauten Kontexten
  /// Das KMK-Ziel, das alle Schüler erreichen sollen
  regular,

  /// Stufe IV: Regelstandard plus — sicheres Anwenden auch in neuen Kontexten
  /// Verknüpfungen herstellen, mehrschrittige Lösungswege
  regularPlus,

  /// Stufe V: Optimalstandard — komplexes Modellieren und Reflektieren
  /// Unter optimalen Bedingungen erreichbar
  optimal,
}

/// Anforderungsbereiche nach KMK (I–III), analog zu Blooms Taxonomie
enum RequirementLevel {
  /// AFB I: Reproduzieren — Wiedergeben von Fakten, Anwenden geübter Verfahren
  /// Operatoren: nennen, angeben, beschreiben, wiedergeben, berechnen (Standardverfahren)
  reproduce,

  /// AFB II: Zusammenhänge herstellen — Anwenden in neuen Kontexten, Erklären
  /// Operatoren: erklären, vergleichen, begründen, anwenden, untersuchen
  transfer,

  /// AFB III: Verallgemeinern/Reflektieren — Beurteilen, Beweisen, Problemlösen
  /// Operatoren: beurteilen, erörtern, beweisen, entwickeln, interpretieren
  reflect,
}

/// Schwierigkeitsprofil für die Aufgabengenerierung
class DifficultyProfile {
  /// Anteil leichter Aufgaben (AFB I, Reproduzieren)
  final double easyRatio;

  /// Anteil mittlerer Aufgaben (AFB II, Transfer)
  final double mediumRatio;

  /// Anteil schwerer Aufgaben (AFB III, Reflektieren)
  final double hardRatio;

  /// IQB-Kompetenzstufe
  final CompetencyLevel competencyLevel;

  /// Beschreibung für den Prompt, was der Schüler auf diesem Niveau kann
  final String competencyDescription;

  /// Erlaubte Operatoren (steuern die Aufgabenformulierung)
  final List<String> allowedOperators;

  const DifficultyProfile({
    required this.easyRatio,
    required this.mediumRatio,
    required this.hardRatio,
    required this.competencyLevel,
    required this.competencyDescription,
    required this.allowedOperators,
  });
}

/// Themenblock eines Fachs für eine bestimmte Klassenstufe + Schulform
class CurriculumTopic {
  /// Leitidee / Kompetenzbereich (z.B. "Zahl und Variable", "Sprechen und Zuhören")
  final String competencyArea;

  /// Konkretes Thema (z.B. "Lineare Gleichungen", "Satzglieder bestimmen")
  final String topic;

  /// Beispiel-Lernziele (konkreter als das Thema)
  final List<String> learningGoals;

  /// Typische Aufgabenformate / Operatoren für dieses Thema
  final List<String> typicalOperators;

  /// Was NICHT auf diesem Niveau erwartet wird (hilft Gemini, das Niveau einzuhalten)
  final List<String> notExpected;

  const CurriculumTopic({
    required this.competencyArea,
    required this.topic,
    required this.learningGoals,
    required this.typicalOperators,
    this.notExpected = const [],
  });
}

// ============================================================================
// HAUPTKLASSE: Zugriff auf alle Lehrplandaten
// ============================================================================

class CurriculumData {
  CurriculumData._(); // Nicht instanziierbar

  // ── KOMPETENZSTUFE AUS APP-LEVEL ABLEITEN ──────────────────────────────

  /// Mapped das App-Level (1–∞) auf eine IQB-Kompetenzstufe.
  ///
  /// Level 1–2   → Stufe I  (unter Mindeststandard, Förderbedarf)
  /// Level 3–4   → Stufe II (Mindeststandard)
  /// Level 5–7   → Stufe III (Regelstandard — das KMK-Ziel)
  /// Level 8–10  → Stufe IV (Regelstandard plus)
  /// Level 11+   → Stufe V  (Optimalstandard)
  static CompetencyLevel getCompetencyLevel(int level) {
    if (level <= 2) return CompetencyLevel.belowMinimum;
    if (level <= 4) return CompetencyLevel.minimum;
    if (level <= 7) return CompetencyLevel.regular;
    if (level <= 10) return CompetencyLevel.regularPlus;
    return CompetencyLevel.optimal;
  }

  // ── SCHWIERIGKEITSPROFIL NACH SCHULFORM + LEVEL ────────────────────────

  /// Gibt ein Schwierigkeitsprofil zurück, das die Aufgabenverteilung
  /// basierend auf Schulform und App-Level steuert.
  ///
  /// Gymnasium hat grundsätzlich höhere Anforderungen als Realschule,
  /// die wiederum höher sind als Hauptschule — bei gleichem Level.
  /// Die Gesamtschule wird über den Kurs (G/E) differenziert, für
  /// die App mappen wir sie basierend auf dem Level.
  static DifficultyProfile getDifficultyProfile({
    required String schoolType,
    required int level,
  }) {
    final competency = getCompetencyLevel(level);

    // Gesamtschule: Level < 5 → G-Kurs-Niveau (≈ Hauptschule),
    //               Level >= 5 → E-Kurs-Niveau (≈ Realschule/Gymnasium)
    final effectiveSchoolType = _resolveSchoolType(schoolType, level);

    switch (effectiveSchoolType) {
      case 'Hauptschule':
        return _hauptschuleProfile(competency);
      case 'Realschule':
        return _realschuleProfile(competency);
      case 'Gymnasium':
        return _gymnasiumProfile(competency);
      case 'Grundschule':
        return _grundschuleProfile(competency);
      default:
        return _realschuleProfile(competency); // Fallback
    }
  }

  /// Löst Gesamtschule in ein effektives Schulform-Niveau auf
  static String _resolveSchoolType(String schoolType, int level) {
    if (schoolType == 'Gesamtschule') {
      // G-Kurs ≈ Hauptschule, E-Kurs ≈ Realschule/Gymnasium
      if (level <= 4) return 'Hauptschule';
      if (level <= 8) return 'Realschule';
      return 'Gymnasium';
    }
    return schoolType;
  }

  static DifficultyProfile _grundschuleProfile(CompetencyLevel c) {
    switch (c) {
      case CompetencyLevel.belowMinimum:
        return const DifficultyProfile(
          easyRatio: 0.70,
          mediumRatio: 0.25,
          hardRatio: 0.05,
          competencyLevel: CompetencyLevel.belowMinimum,
          competencyDescription:
              'Reproduziere einfachste Fakten. Nur stark geübte Aufgaben in bekanntem Format. '
              'Einfache Zahlen, kurze Wörter, unterstützende Bilder/Beispiele hilfreich.',
          allowedOperators: [
            'nennen',
            'angeben',
            'aufzählen',
            'berechnen (einfach)',
          ],
        );
      case CompetencyLevel.minimum:
        return const DifficultyProfile(
          easyRatio: 0.50,
          mediumRatio: 0.40,
          hardRatio: 0.10,
          competencyLevel: CompetencyLevel.minimum,
          competencyDescription:
              'Einfache Anwendungen in klarem Kontext. Grundrechenarten sicher, '
              'einfache Sachaufgaben mit überschaubaren Zahlen.',
          allowedOperators: [
            'nennen',
            'angeben',
            'beschreiben',
            'berechnen',
            'ordnen',
          ],
        );
      case CompetencyLevel.regular:
        return const DifficultyProfile(
          easyRatio: 0.35,
          mediumRatio: 0.45,
          hardRatio: 0.20,
          competencyLevel: CompetencyLevel.regular,
          competencyDescription:
              'Flexibles Anwenden in vertrauten Kontexten. Sachaufgaben mit mehreren Schritten, '
              'einfache Schätzungen, Wissen auf variierte Probleme übertragen.',
          allowedOperators: [
            'nennen',
            'beschreiben',
            'berechnen',
            'erklären',
            'vergleichen',
            'begründen (einfach)',
          ],
        );
      case CompetencyLevel.regularPlus:
        return const DifficultyProfile(
          easyRatio: 0.20,
          mediumRatio: 0.50,
          hardRatio: 0.30,
          competencyLevel: CompetencyLevel.regularPlus,
          competencyDescription:
              'Sicheres Anwenden auch in unbekannten Kontexten. Komplexere Sachaufgaben, '
              'eigene Lösungswege finden, Ergebnisse überprüfen.',
          allowedOperators: [
            'beschreiben',
            'berechnen',
            'erklären',
            'vergleichen',
            'begründen',
            'untersuchen',
          ],
        );
      case CompetencyLevel.optimal:
        return const DifficultyProfile(
          easyRatio: 0.10,
          mediumRatio: 0.45,
          hardRatio: 0.45,
          competencyLevel: CompetencyLevel.optimal,
          competencyDescription:
              'Komplexes Modellieren und Reflektieren. Eigene Strategien entwickeln, '
              'komplexe Sachsituationen modellieren, mathematische Begründungen formulieren.',
          allowedOperators: [
            'erklären',
            'vergleichen',
            'begründen',
            'untersuchen',
            'beurteilen',
            'entwickeln',
          ],
        );
    }
  }

  static DifficultyProfile _hauptschuleProfile(CompetencyLevel c) {
    switch (c) {
      case CompetencyLevel.belowMinimum:
        return const DifficultyProfile(
          easyRatio: 0.70,
          mediumRatio: 0.25,
          hardRatio: 0.05,
          competencyLevel: CompetencyLevel.belowMinimum,
          competencyDescription:
              'Starker Förderbedarf. Nur einfachste Reproduktionsaufgaben. '
              'Alltagsnahe Kontexte, kleine Zahlen, kurze Texte, keine Abstraktion.',
          allowedOperators: [
            'nennen',
            'angeben',
            'berechnen (Grundrechenarten)',
          ],
        );
      case CompetencyLevel.minimum:
        return const DifficultyProfile(
          easyRatio: 0.55,
          mediumRatio: 0.35,
          hardRatio: 0.10,
          competencyLevel: CompetencyLevel.minimum,
          competencyDescription:
              'Mindeststandard (HSA-Niveau). Grundlegende Verfahren in bekannten Kontexten anwenden. '
              'Einfache Sachaufgaben, überschaubare Texte, klare Aufgabenstellung.',
          allowedOperators: [
            'nennen',
            'angeben',
            'beschreiben',
            'berechnen',
            'ordnen',
            'zuordnen',
          ],
        );
      case CompetencyLevel.regular:
        return const DifficultyProfile(
          easyRatio: 0.40,
          mediumRatio: 0.40,
          hardRatio: 0.20,
          competencyLevel: CompetencyLevel.regular,
          competencyDescription:
              'Regelstandard (HSA). Wissen flexibel auf variierte Alltagsprobleme anwenden. '
              'Mehrschrittige Aufgaben in vertrauten Kontexten, einfache Begründungen.',
          allowedOperators: [
            'beschreiben',
            'berechnen',
            'erklären',
            'vergleichen',
            'zuordnen',
            'begründen (einfach)',
          ],
        );
      case CompetencyLevel.regularPlus:
        return const DifficultyProfile(
          easyRatio: 0.25,
          mediumRatio: 0.45,
          hardRatio: 0.30,
          competencyLevel: CompetencyLevel.regularPlus,
          competencyDescription:
              'Über HSA-Erwartungen. Sichere Anwendung in leicht unbekannten Kontexten. '
              'Zusammenhänge erkennen, einfache Verallgemeinerungen.',
          allowedOperators: [
            'beschreiben',
            'erklären',
            'vergleichen',
            'begründen',
            'anwenden',
            'untersuchen',
          ],
        );
      case CompetencyLevel.optimal:
        return const DifficultyProfile(
          easyRatio: 0.15,
          mediumRatio: 0.45,
          hardRatio: 0.40,
          competencyLevel: CompetencyLevel.optimal,
          competencyDescription:
              'Optimalstandard (HSA) / Mindeststandard (MSA). Komplexere Probleme selbstständig lösen. '
              'Mehrschrittige Verfahren, Ergebnisse reflektieren.',
          allowedOperators: [
            'erklären',
            'vergleichen',
            'begründen',
            'untersuchen',
            'anwenden',
            'beurteilen (einfach)',
          ],
        );
    }
  }

  static DifficultyProfile _realschuleProfile(CompetencyLevel c) {
    switch (c) {
      case CompetencyLevel.belowMinimum:
        return const DifficultyProfile(
          easyRatio: 0.60,
          mediumRatio: 0.30,
          hardRatio: 0.10,
          competencyLevel: CompetencyLevel.belowMinimum,
          competencyDescription:
              'Förderbedarf auf Realschulniveau. Grundlegende Aufgaben mit klarer Struktur. '
              'Bekannte Aufgabenformate, schrittweise Anleitungen, keine Abstraktion nötig.',
          allowedOperators: ['nennen', 'angeben', 'beschreiben', 'berechnen'],
        );
      case CompetencyLevel.minimum:
        return const DifficultyProfile(
          easyRatio: 0.45,
          mediumRatio: 0.40,
          hardRatio: 0.15,
          competencyLevel: CompetencyLevel.minimum,
          competencyDescription:
              'Mindeststandard (MSA-Niveau). Routineverfahren sicher anwenden. '
              'Aufgaben in vertrauten Kontexten, einfache Zusammenhänge erkennen.',
          allowedOperators: [
            'nennen',
            'beschreiben',
            'berechnen',
            'erklären',
            'vergleichen',
            'zuordnen',
          ],
        );
      case CompetencyLevel.regular:
        return const DifficultyProfile(
          easyRatio: 0.30,
          mediumRatio: 0.45,
          hardRatio: 0.25,
          competencyLevel: CompetencyLevel.regular,
          competencyDescription:
              'Regelstandard (MSA). Flexibles Anwenden, auch in leicht variierten Kontexten. '
              'Mehrschrittige Lösungswege, Zusammenhänge erklären und begründen.',
          allowedOperators: [
            'beschreiben',
            'berechnen',
            'erklären',
            'vergleichen',
            'begründen',
            'anwenden',
            'untersuchen',
          ],
        );
      case CompetencyLevel.regularPlus:
        return const DifficultyProfile(
          easyRatio: 0.20,
          mediumRatio: 0.45,
          hardRatio: 0.35,
          competencyLevel: CompetencyLevel.regularPlus,
          competencyDescription:
              'Über MSA-Erwartungen. Sicheres Anwenden in unbekannten Kontexten. '
              'Komplexe Zusammenhänge verknüpfen, eigene Lösungsstrategien entwickeln.',
          allowedOperators: [
            'erklären',
            'vergleichen',
            'begründen',
            'untersuchen',
            'anwenden',
            'analysieren',
            'beurteilen',
          ],
        );
      case CompetencyLevel.optimal:
        return const DifficultyProfile(
          easyRatio: 0.10,
          mediumRatio: 0.40,
          hardRatio: 0.50,
          competencyLevel: CompetencyLevel.optimal,
          competencyDescription:
              'Optimalstandard (MSA). Komplexe Modellierung, Reflexion und Verallgemeinerung. '
              'Kreative Lösungswege, mathematische Argumentation, kritische Bewertung.',
          allowedOperators: [
            'erklären',
            'begründen',
            'analysieren',
            'beurteilen',
            'entwickeln',
            'interpretieren',
          ],
        );
    }
  }

  static DifficultyProfile _gymnasiumProfile(CompetencyLevel c) {
    switch (c) {
      case CompetencyLevel.belowMinimum:
        return const DifficultyProfile(
          easyRatio: 0.55,
          mediumRatio: 0.35,
          hardRatio: 0.10,
          competencyLevel: CompetencyLevel.belowMinimum,
          competencyDescription:
              'Förderbedarf auf Gymnasialniveau. Grundverfahren festigen. '
              'Geübte Aufgabentypen, aber bereits mit Fachsprache und leichter Abstraktion.',
          allowedOperators: [
            'nennen',
            'angeben',
            'beschreiben',
            'berechnen',
            'bestimmen',
          ],
        );
      case CompetencyLevel.minimum:
        return const DifficultyProfile(
          easyRatio: 0.35,
          mediumRatio: 0.45,
          hardRatio: 0.20,
          competencyLevel: CompetencyLevel.minimum,
          competencyDescription:
              'Mindeststandard (Gymnasium). Routineverfahren sicher, einfache Transfers. '
              'Fachsprache verwenden, Ergebnisse in eigenen Worten wiedergeben.',
          allowedOperators: [
            'beschreiben',
            'berechnen',
            'bestimmen',
            'erklären',
            'vergleichen',
            'darstellen',
          ],
        );
      case CompetencyLevel.regular:
        return const DifficultyProfile(
          easyRatio: 0.25,
          mediumRatio: 0.45,
          hardRatio: 0.30,
          competencyLevel: CompetencyLevel.regular,
          competencyDescription:
              'Regelstandard (Gymnasium). Flexibles Anwenden in neuen Kontexten. '
              'Mehrschrittige Aufgaben, Fachbegriffe präzise nutzen, Zusammenhänge begründen.',
          allowedOperators: [
            'erklären',
            'vergleichen',
            'begründen',
            'anwenden',
            'untersuchen',
            'darstellen',
            'analysieren',
          ],
        );
      case CompetencyLevel.regularPlus:
        return const DifficultyProfile(
          easyRatio: 0.15,
          mediumRatio: 0.40,
          hardRatio: 0.45,
          competencyLevel: CompetencyLevel.regularPlus,
          competencyDescription:
              'Über Regelstandard (Gymnasium). Eigenständige Strategieentwicklung. '
              'Komplexe Sachverhalte analysieren, formale Beweise führen, '
              'Modellierungsaufgaben mit mehreren Variablen.',
          allowedOperators: [
            'begründen',
            'analysieren',
            'beurteilen',
            'untersuchen',
            'beweisen',
            'interpretieren',
            'entwickeln',
          ],
        );
      case CompetencyLevel.optimal:
        return const DifficultyProfile(
          easyRatio: 0.05,
          mediumRatio: 0.35,
          hardRatio: 0.60,
          competencyLevel: CompetencyLevel.optimal,
          competencyDescription:
              'Optimalstandard (Gymnasium/Abiturniveau). Komplexe Modellierung und Reflexion. '
              'Beweise führen, Gegenbeispiele konstruieren, kreative Problemlösung, '
              'Ergebnisse kritisch bewerten und verallgemeinern.',
          allowedOperators: [
            'analysieren',
            'beurteilen',
            'beweisen',
            'entwickeln',
            'interpretieren',
            'erörtern',
            'reflektieren',
          ],
        );
    }
  }

  // ── LEHRPLAN-THEMEN NACH SCHULFORM, KLASSE, FACH ───────────────────────

  /// Gibt die Lehrplanthemen für die Kombination Schulform + Klasse + Fach zurück.
  /// Wenn keine spezifischen Daten vorhanden sind, wird ein sinnvoller Fallback geliefert.
  static List<CurriculumTopic> getTopics({
    required String schoolType,
    required int grade,
    required String subject,
    required int level,
  }) {
    final effectiveSchoolType = _resolveSchoolType(schoolType, level);
    final key = '${effectiveSchoolType}_${grade}_${subject.toLowerCase()}';

    return _topicDatabase[key] ??
        _getFallbackTopics(effectiveSchoolType, grade, subject);
  }

  /// Erzeugt einen strukturierten Lehrplan-Kontext-String für den AI-Prompt
  static String buildCurriculumContext({
    required String schoolType,
    required int grade,
    required String subject,
    required int level,
  }) {
    final topics = getTopics(
      schoolType: schoolType,
      grade: grade,
      subject: subject,
      level: level,
    );
    final profile = getDifficultyProfile(schoolType: schoolType, level: level);
    final effectiveSchoolType = _resolveSchoolType(schoolType, level);

    final buffer = StringBuffer();

    // Schulform-Kontext
    buffer.writeln('SCHULFORM-KONTEXT:');
    buffer.writeln('- Effektives Niveau: $effectiveSchoolType');
    if (schoolType == 'Gesamtschule') {
      if (level <= 4) {
        buffer.writeln(
          '- Gesamtschule G-Kurs (Grundkurs) — entspricht Hauptschulniveau',
        );
      } else if (level <= 8) {
        buffer.writeln(
          '- Gesamtschule E-Kurs (Erweiterungskurs) — entspricht Realschulniveau',
        );
      } else {
        buffer.writeln(
          '- Gesamtschule E-Kurs (oberes Niveau) — entspricht Gymnasialniveau',
        );
      }
    }
    buffer.writeln('- Zielabschluss: ${_targetDegree(effectiveSchoolType)}');
    buffer.writeln();

    // Kompetenzstufe
    buffer.writeln('KOMPETENZSTUFE (IQB-basiert):');
    buffer.writeln('- ${profile.competencyDescription}');
    buffer.writeln(
      '- Erlaubte Operatoren: ${profile.allowedOperators.join(", ")}',
    );
    buffer.writeln();

    // Schwierigkeitsverteilung
    final easyCount = (profile.easyRatio * 10).round();
    final mediumCount = (profile.mediumRatio * 10).round();
    final hardCount = 10 - easyCount - mediumCount;
    buffer.writeln('SCHWIERIGKEITSVERTEILUNG (von 10 Fragen):');
    buffer.writeln(
      '- $easyCount× leicht (AFB I: Reproduzieren — nennen, angeben, berechnen)',
    );
    buffer.writeln(
      '- $mediumCount× mittel (AFB II: Transfer — erklären, vergleichen, begründen)',
    );
    buffer.writeln(
      '- $hardCount× schwer (AFB III: Reflexion — analysieren, beurteilen, entwickeln)',
    );
    buffer.writeln();

    // Lehrplanthemen
    if (topics.isNotEmpty) {
      buffer.writeln(
        'AKTUELLE LEHRPLANTHEMEN für Klasse $grade ($effectiveSchoolType):',
      );
      for (final topic in topics) {
        buffer.writeln('  📌 ${topic.competencyArea}: ${topic.topic}');
        for (final goal in topic.learningGoals) {
          buffer.writeln('     - $goal');
        }
        if (topic.notExpected.isNotEmpty) {
          buffer.writeln(
            '     ⚠️ NICHT erwartet: ${topic.notExpected.join(", ")}',
          );
        }
      }
    }

    return buffer.toString();
  }

  static String _targetDegree(String schoolType) {
    switch (schoolType) {
      case 'Hauptschule':
        return 'Erster Schulabschluss (ESA / Hauptschulabschluss nach Klasse 9/10)';
      case 'Realschule':
        return 'Mittlerer Schulabschluss (MSA / Fachoberschulreife nach Klasse 10)';
      case 'Gymnasium':
        return 'Allgemeine Hochschulreife (Abitur nach Klasse 12/13)';
      case 'Grundschule':
        return 'Primarbereich (Übergang in Sekundarstufe I nach Klasse 4)';
      default:
        return 'Mittlerer Schulabschluss (MSA)';
    }
  }

  // ── FALLBACK-THEMEN ────────────────────────────────────────────────────

  static List<CurriculumTopic> _getFallbackTopics(
    String schoolType,
    int grade,
    String subject,
  ) {
    // Generischer Fallback wenn keine spezifischen Daten vorhanden
    return [
      CurriculumTopic(
        competencyArea: 'Allgemein',
        topic: 'Altersgerechte Inhalte für Klasse $grade ($schoolType)',
        learningGoals: [
          'Grundlegende Konzepte des Fachs $subject für Klasse $grade beherrschen',
          'Aufgaben mit altersgerechtem Schwierigkeitsgrad lösen',
        ],
        typicalOperators: ['nennen', 'beschreiben', 'erklären'],
      ),
    ];
  }

  // ════════════════════════════════════════════════════════════════════════
  // 📖 THEMEN-DATENBANK
  //
  // Schlüssel: "{Schulform}_{Klasse}_{fach}"
  // Die Daten basieren auf den offiziellen Lehrplänen (Bayern, NRW).
  // ════════════════════════════════════════════════════════════════════════

  static final Map<String, List<CurriculumTopic>> _topicDatabase = {
    // ══════════════════════════════════════════════════════════════════════
    // GRUNDSCHULE — MATHEMATIK
    // ══════════════════════════════════════════════════════════════════════
    'Grundschule_1_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Zahlenraum bis 20',
        learningGoals: [
          'Zahlen bis 20 lesen, schreiben und der Größe nach ordnen',
          'Addition und Subtraktion im Zahlenraum bis 20',
          'Verdoppeln und Halbieren',
          'Nachbarzahlen und Zahlenreihen ergänzen',
        ],
        typicalOperators: ['berechnen', 'ordnen', 'ergänzen'],
        notExpected: ['Multiplikation', 'Division', 'Zahlen über 20'],
      ),
      CurriculumTopic(
        competencyArea: 'Raum und Form',
        topic: 'Geometrische Grundformen',
        learningGoals: [
          'Kreis, Dreieck, Viereck/Rechteck erkennen und benennen',
          'Formen in der Umgebung wiedererkennen',
        ],
        typicalOperators: ['benennen', 'zuordnen', 'erkennen'],
        notExpected: ['Flächen berechnen', 'Koordinaten'],
      ),
    ],

    'Grundschule_2_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Zahlenraum bis 100',
        learningGoals: [
          'Addition und Subtraktion im Zahlenraum bis 100',
          'Einmaleins-Reihen (2, 5, 10) kennenlernen',
          'Stellenwerttafel (Einer, Zehner) verstehen',
          'Einfache Sachaufgaben mit Addition/Subtraktion',
        ],
        typicalOperators: ['berechnen', 'ordnen', 'ergänzen', 'lösen'],
        notExpected: [
          'Schriftliche Multiplikation',
          'Brüche',
          'Negative Zahlen',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Größen und Messen',
        topic: 'Geld und Zeit',
        learningGoals: [
          'Euro und Cent kennen und umrechnen',
          'Uhrzeiten lesen (volle und halbe Stunden)',
        ],
        typicalOperators: ['berechnen', 'ablesen', 'umrechnen'],
      ),
    ],

    'Grundschule_3_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Zahlenraum bis 1000',
        learningGoals: [
          'Zahlen bis 1000 lesen, schreiben, vergleichen und ordnen',
          'Halbschriftliche Addition und Subtraktion',
          'Einmaleins aller Reihen (1–10) sicher beherrschen',
          'Sachaufgaben mit mehreren Rechenschritten',
        ],
        typicalOperators: ['berechnen', 'vergleichen', 'ordnen', 'lösen'],
        notExpected: [
          'Schriftliche Division',
          'Bruchrechnung',
          'Dezimalzahlen',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Raum und Form',
        topic: 'Geometrie — Flächen und Symmetrie',
        learningGoals: [
          'Achsensymmetrie erkennen und zeichnen',
          'Rechteck und Quadrat unterscheiden',
          'Umfang einfacher Figuren berechnen',
        ],
        typicalOperators: ['erkennen', 'zeichnen', 'berechnen'],
      ),
    ],

    'Grundschule_4_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Zahlenraum bis 1.000.000',
        learningGoals: [
          'Schriftliche Addition, Subtraktion, Multiplikation und Division',
          'Zahlen bis 1 Million darstellen, vergleichen und runden',
          'Sachaufgaben mit mehreren Rechenschritten und Operationen',
          'Überschlag und Kontrolle von Ergebnissen',
        ],
        typicalOperators: [
          'berechnen',
          'runden',
          'schätzen',
          'lösen',
          'prüfen',
        ],
        notExpected: [
          'Brüche kürzen',
          'Dezimaldivision',
          'Negative Zahlen',
          'Variablen',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Größen und Messen',
        topic: 'Längen, Gewichte, Zeiten',
        learningGoals: [
          'Umrechnungen: mm–cm–m–km, g–kg–t, s–min–h',
          'Sachaufgaben mit Größen',
        ],
        typicalOperators: ['umrechnen', 'berechnen', 'vergleichen'],
      ),
      CurriculumTopic(
        competencyArea: 'Raum und Form',
        topic: 'Fläche und Umfang',
        learningGoals: [
          'Umfang und Flächeninhalt von Rechteck und Quadrat berechnen',
          'Würfel und Quader erkennen und Netze zeichnen',
        ],
        typicalOperators: ['berechnen', 'zeichnen', 'erkennen'],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // GRUNDSCHULE — DEUTSCH
    // ══════════════════════════════════════════════════════════════════════
    'Grundschule_3_deutsch': const [
      CurriculumTopic(
        competencyArea: 'Sprache und Sprachgebrauch untersuchen',
        topic: 'Wortarten',
        learningGoals: [
          'Nomen, Verben und Adjektive sicher erkennen und unterscheiden',
          'Nomen mit Artikeln (der, die, das) verwenden',
          'Verben in Grundform und gebeugte Form kennen',
          'Adjektive als Wie-Wörter verstehen und steigern',
        ],
        typicalOperators: ['benennen', 'zuordnen', 'bilden', 'unterscheiden'],
        notExpected: ['Konjunktiv', 'Passivformen', 'Satzgliedanalyse'],
      ),
      CurriculumTopic(
        competencyArea: 'Richtig schreiben',
        topic: 'Rechtschreibstrategien',
        learningGoals: [
          'Silbentrennung anwenden',
          'Großschreibung von Nomen beachten',
          'Doppelte Mitlaute und Dehnungs-h',
          'Wörter mit ie, ä/äu, eu',
        ],
        typicalOperators: ['schreiben', 'trennen', 'ergänzen', 'korrigieren'],
      ),
    ],

    'Grundschule_4_deutsch': const [
      CurriculumTopic(
        competencyArea: 'Sprache und Sprachgebrauch untersuchen',
        topic: 'Satzglieder und Zeitformen',
        learningGoals: [
          'Subjekt und Prädikat bestimmen',
          'Zeitformen: Präsens, Präteritum, Perfekt, Futur erkennen und bilden',
          'Wörtliche Rede mit Begleitsatz und Satzzeichen',
          'Satzarten unterscheiden: Aussage-, Frage-, Ausrufesatz',
        ],
        typicalOperators: ['bestimmen', 'bilden', 'umformen', 'unterscheiden'],
        notExpected: ['Plusquamperfekt', 'Passiv', 'Adverbialsätze'],
      ),
      CurriculumTopic(
        competencyArea: 'Texte schreiben',
        topic: 'Texte planen und verfassen',
        learningGoals: [
          'Bildergeschichten schreiben (Einleitung, Hauptteil, Schluss)',
          'Briefe schreiben (Anrede, Inhalt, Gruß)',
          'Vorgangsbeschreibungen verfassen',
        ],
        typicalOperators: ['schreiben', 'ordnen', 'beschreiben', 'erzählen'],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // GRUNDSCHULE — ENGLISCH
    // ══════════════════════════════════════════════════════════════════════
    'Grundschule_3_englisch': const [
      CurriculumTopic(
        competencyArea: 'Kommunikative Kompetenzen',
        topic: 'Grundwortschatz und erste Sätze',
        learningGoals: [
          'Begrüßung und Verabschiedung (Hello, Goodbye, Good morning)',
          'Sich vorstellen (My name is..., I am ... years old)',
          'Farben, Zahlen 1–20, Tiere, Familie, Schulsachen benennen',
          'Einfache Fragen verstehen und beantworten (What is this? / Do you like...?)',
        ],
        typicalOperators: ['benennen', 'zuordnen', 'antworten'],
        notExpected: [
          'Grammatikregeln erklären',
          'Texte schreiben',
          'Zeitformen',
        ],
      ),
    ],

    'Grundschule_4_englisch': const [
      CurriculumTopic(
        competencyArea: 'Kommunikative Kompetenzen',
        topic: 'Wortschatz erweitern und einfache Dialoge',
        learningGoals: [
          'Wortschatz: Hobbies, Essen, Kleidung, Wetter, Körperteile',
          'Einfache Sätze bilden (I like..., I can..., I have got...)',
          'Kurze Dialoge führen (Im Geschäft, Freunde vorstellen)',
          'Einfache Texte/Lieder verstehen',
        ],
        typicalOperators: ['benennen', 'zuordnen', 'ergänzen', 'übersetzen'],
        notExpected: ['Grammatikregeln', 'Aufsätze', 'Passive Voice'],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // GRUNDSCHULE — SACHKUNDE
    // ══════════════════════════════════════════════════════════════════════
    'Grundschule_3_sachkunde': const [
      CurriculumTopic(
        competencyArea: 'Natur und Umwelt',
        topic: 'Tiere, Pflanzen, Lebensräume',
        learningGoals: [
          'Heimische Tiere und ihre Lebensräume kennen (Wald, Wiese, Wasser)',
          'Teile einer Pflanze benennen (Wurzel, Stängel, Blatt, Blüte)',
          'Jahreszeiten und ihre Merkmale',
          'Wetter beobachten und beschreiben',
        ],
        typicalOperators: [
          'benennen',
          'beschreiben',
          'zuordnen',
          'vergleichen',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Technik und Arbeit',
        topic: 'Strom und Magnetismus',
        learningGoals: [
          'Einfachen Stromkreis verstehen (Batterie, Kabel, Lampe)',
          'Leiter und Nichtleiter unterscheiden',
          'Magnete: Nord-/Südpol, Anziehung/Abstoßung',
        ],
        typicalOperators: ['benennen', 'erklären', 'unterscheiden'],
      ),
    ],

    'Grundschule_4_sachkunde': const [
      CurriculumTopic(
        competencyArea: 'Natur und Umwelt',
        topic: 'Wasser und Umweltschutz',
        learningGoals: [
          'Wasserkreislauf verstehen (Verdunstung, Wolken, Regen)',
          'Aggregatzustände: fest, flüssig, gasförmig',
          'Gewässerschutz und Umweltverschmutzung',
          'Mülltrennung und Recycling',
        ],
        typicalOperators: ['beschreiben', 'erklären', 'zuordnen'],
      ),
      CurriculumTopic(
        competencyArea: 'Raum und Mobilität',
        topic: 'Deutschland und Europa',
        learningGoals: [
          'Bundesländer und ihre Hauptstädte kennen',
          'Himmelsrichtungen und Kartenarbeit',
          'Nachbarländer Deutschlands',
        ],
        typicalOperators: ['benennen', 'zuordnen', 'beschreiben'],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // HAUPTSCHULE — MATHEMATIK (Klasse 5–9)
    // ══════════════════════════════════════════════════════════════════════
    'Hauptschule_5_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Natürliche Zahlen im erweiterten Zahlenraum',
        learningGoals: [
          'Zahlen bis 1 Million darstellen und vergleichen',
          'Grundrechenarten sicher beherrschen (auch schriftlich)',
          'Runden, Überschlagen und Ergebnisse kontrollieren',
          'Einfache Sachaufgaben aus dem Alltag lösen',
        ],
        typicalOperators: ['berechnen', 'runden', 'schätzen', 'lösen'],
        notExpected: ['Bruchrechnung', 'Negative Zahlen', 'Variablen'],
      ),
    ],

    'Hauptschule_6_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Brüche und Dezimalzahlen — Grundlagen',
        learningGoals: [
          'Brüche als Teile eines Ganzen verstehen (Pizza, Torte)',
          'Einfache Brüche vergleichen und ordnen',
          'Dezimalzahlen in Alltagskontexten (Geld, Länge)',
          'Umwandlung: einfache Brüche ↔ Dezimalzahlen (1/2, 1/4, 3/4)',
        ],
        typicalOperators: ['berechnen', 'vergleichen', 'umwandeln', 'ordnen'],
        notExpected: [
          'Bruchrechnung mit verschiedenen Nennern',
          'Negative Zahlen',
        ],
      ),
    ],

    'Hauptschule_7_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Prozentrechnung und rationale Zahlen',
        learningGoals: [
          'Prozent als „von Hundert" verstehen',
          'Prozentwert, Grundwert und Prozentsatz in Alltagssituationen berechnen',
          'Einfache Diagramme (Kreis, Säulen) ablesen und interpretieren',
          'Negative Zahlen in konkreten Kontexten (Temperatur, Schulden)',
          'Addition und Subtraktion rationaler Zahlen am Zahlenstrahl',
        ],
        typicalOperators: ['berechnen', 'ablesen', 'zuordnen', 'vergleichen'],
        notExpected: [
          'Formale Algebra',
          'Terme mit Variablen',
          'Gleichungen',
          'Boxplots',
          'Satz des Thales',
          'Mathematische Beweise',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Raum und Form',
        topic: 'Winkel und parallele Geraden',
        learningGoals: [
          'Winkelarten benennen (spitz, recht, stumpf)',
          'Winkel messen und zeichnen mit dem Geodreieck',
          'Parallele und senkrechte Geraden erkennen',
        ],
        typicalOperators: ['messen', 'zeichnen', 'benennen', 'erkennen'],
      ),
    ],

    'Hauptschule_8_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Zinsrechnung und Zuordnungen',
        learningGoals: [
          'Einfache Zinsrechnung (Jahreszins)',
          'Proportionale Zuordnungen (Dreisatz) in Alltagssituationen',
          'Tabellen und Diagramme erstellen und auswerten',
        ],
        typicalOperators: ['berechnen', 'darstellen', 'ablesen', 'zuordnen'],
        notExpected: [
          'Lineare Funktionen',
          'Zinseszins',
          'Formale Gleichungssysteme',
        ],
      ),
    ],

    'Hauptschule_9_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Flächen, Körper und Prüfungsvorbereitung (HSA)',
        learningGoals: [
          'Flächenberechnung: Dreieck, Parallelogramm, Trapez',
          'Volumen von Quader und Prisma',
          'Sachaufgaben aus dem Alltag (Einkaufen, Rabatte, Entfernungen)',
          'Grundlagen der Wahrscheinlichkeitsrechnung (Münzwurf, Würfel)',
        ],
        typicalOperators: ['berechnen', 'lösen', 'erklären', 'anwenden'],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // REALSCHULE — MATHEMATIK (Klasse 5–10)
    // ══════════════════════════════════════════════════════════════════════
    'Realschule_5_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahlen und Operationen',
        topic: 'Natürliche Zahlen und Rechengesetze',
        learningGoals: [
          'Große Zahlen darstellen (Stellenwerttafel, Zahlenstrahl)',
          'Rechengesetze: Kommutativ-, Assoziativ-, Distributivgesetz',
          'Terme mit Klammern berechnen (Punkt-vor-Strich)',
          'Teiler, Vielfache, Teilbarkeitsregeln',
        ],
        typicalOperators: ['berechnen', 'angeben', 'anwenden', 'begründen'],
        notExpected: ['Negative Zahlen', 'Variablen', 'Gleichungen'],
      ),
    ],

    'Realschule_7_mathe': const [
      CurriculumTopic(
        competencyArea: 'Funktionaler Zusammenhang',
        topic: 'Proportionalität, Dreisatz und Prozentrechnung',
        learningGoals: [
          'Proportionale und antiproportionale Zuordnungen unterscheiden',
          'Dreisatz sicher anwenden',
          'Prozentrechnung: Grundwert, Prozentwert, Prozentsatz',
          'Zinsrechnung (einfache Jahreszinsen)',
          'Diagramme erstellen und kritisch auswerten',
        ],
        typicalOperators: [
          'berechnen',
          'vergleichen',
          'unterscheiden',
          'darstellen',
          'auswerten',
        ],
        notExpected: [
          'Lineare Gleichungssysteme',
          'Satz des Thales',
          'Formale Beweise',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Zahl und Variable',
        topic: 'Terme und einfache Gleichungen',
        learningGoals: [
          'Einfache Terme mit Variablen aufstellen und vereinfachen',
          'Lineare Gleichungen mit einer Variablen lösen',
          'Sachaufgaben in Gleichungen übersetzen',
        ],
        typicalOperators: ['aufstellen', 'vereinfachen', 'lösen', 'erklären'],
        notExpected: [
          'Potenzen mit negativen Exponenten',
          'Klammermultiplikation mit Binomen',
        ],
      ),
    ],

    'Realschule_8_mathe': const [
      CurriculumTopic(
        competencyArea: 'Funktionaler Zusammenhang',
        topic: 'Lineare Funktionen',
        learningGoals: [
          'Lineare Funktionen y = mx + b verstehen und zeichnen',
          'Steigung und y-Achsenabschnitt bestimmen',
          'Schnittpunkt zweier Geraden berechnen',
          'Sachsituationen mit linearen Funktionen modellieren',
        ],
        typicalOperators: ['berechnen', 'zeichnen', 'bestimmen', 'modellieren'],
      ),
    ],

    'Realschule_10_mathe': const [
      CurriculumTopic(
        competencyArea: 'Funktionaler Zusammenhang',
        topic: 'Quadratische Funktionen und Prüfungsvorbereitung (MSA)',
        learningGoals: [
          'Quadratische Funktionen: Scheitelpunktform, Normalform',
          'Nullstellen berechnen (p-q-Formel)',
          'Trigonometrie im rechtwinkligen Dreieck (sin, cos, tan)',
          'Wahrscheinlichkeitsrechnung und Statistik (Median, Mittelwert)',
        ],
        typicalOperators: [
          'berechnen',
          'anwenden',
          'begründen',
          'interpretieren',
        ],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // GYMNASIUM — MATHEMATIK (Klasse 5–10)
    // ══════════════════════════════════════════════════════════════════════
    'Gymnasium_5_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahl',
        topic: 'Natürliche Zahlen, Rechengesetze und Geometrie-Einstieg',
        learningGoals: [
          'Natürliche Zahlen bis 1 Milliarde: Stellenwerte, Runden',
          'Rechengesetze sicher anwenden (inkl. Distributivgesetz)',
          'Potenzschreibweise für natürliche Zahlen (z.B. 2³ = 8)',
          'Teilbarkeit, Primzahlen, ggT und kgV',
          'Koordinatensystem: Punkte ablesen und einzeichnen',
        ],
        typicalOperators: ['berechnen', 'bestimmen', 'angeben', 'darstellen'],
        notExpected: [
          'Negative Zahlen',
          'Bruchgleichungen',
          'Funktionsbegriff',
        ],
      ),
    ],

    'Gymnasium_6_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahl',
        topic: 'Brüche, Dezimalzahlen und negative Zahlen',
        learningGoals: [
          'Bruchrechnung vollständig: Addition, Subtraktion, Multiplikation, Division',
          'Brüche kürzen und erweitern',
          'Dezimalbrüche und Umwandlung',
          'Einführung negativer Zahlen und Rechnen mit ihnen',
          'Prozentbegriff einführen',
        ],
        typicalOperators: [
          'berechnen',
          'kürzen',
          'erweitern',
          'umwandeln',
          'vergleichen',
        ],
      ),
    ],

    'Gymnasium_7_mathe': const [
      CurriculumTopic(
        competencyArea: 'Zahl und Variable',
        topic: 'Terme, Potenzen und lineare Gleichungen',
        learningGoals: [
          'Terme mit Variablen aufstellen, zusammenfassen, ausmultiplizieren',
          'Distributivgesetz zum Faktorisieren nutzen',
          'Potenzen mit ganzzahligen Exponenten',
          'Lineare Gleichungen und Ungleichungen lösen',
          'Sachaufgaben in Gleichungen modellieren',
        ],
        typicalOperators: [
          'aufstellen',
          'vereinfachen',
          'faktorisieren',
          'lösen',
          'begründen',
          'modellieren',
        ],
        notExpected: [
          'Quadratische Gleichungen',
          'Gleichungssysteme mit mehreren Variablen',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Raum und Form',
        topic: 'Satz des Thales, Konstruktionen',
        learningGoals: [
          'Satz des Thales kennen und anwenden',
          'Umkreis und Inkreis konstruieren',
          'Tangenten an Kreise konstruieren',
          'Kongruenzsätze (SSS, SWS, WSW, SSW) anwenden',
        ],
        typicalOperators: ['konstruieren', 'begründen', 'beweisen', 'anwenden'],
      ),
      CurriculumTopic(
        competencyArea: 'Daten und Zufall',
        topic: 'Statistische Kenngrößen',
        learningGoals: [
          'Median, Quartile und Boxplots erstellen und interpretieren',
          'Mittelwert, Spannweite berechnen',
          'Daten mit Tabellenkalkulation auswerten',
        ],
        typicalOperators: [
          'berechnen',
          'erstellen',
          'interpretieren',
          'vergleichen',
        ],
      ),
    ],

    'Gymnasium_8_mathe': const [
      CurriculumTopic(
        competencyArea: 'Funktionaler Zusammenhang',
        topic: 'Lineare Funktionen und Gleichungssysteme',
        learningGoals: [
          'Lineare Funktionen: Steigung, y-Achsenabschnitt, Geradengleichung',
          'Lineare Gleichungssysteme mit zwei Variablen (Einsetzungs-, Gleichsetzungs-, Additionsverfahren)',
          'Sachaufgaben mit Gleichungssystemen modellieren',
          'Bruchterme vereinfachen',
        ],
        typicalOperators: [
          'aufstellen',
          'lösen',
          'zeichnen',
          'modellieren',
          'interpretieren',
        ],
      ),
      CurriculumTopic(
        competencyArea: 'Raum und Form',
        topic: 'Flächenberechnung und Strahlensätze',
        learningGoals: [
          'Flächeninhalte zusammengesetzter Figuren berechnen',
          'Strahlensätze anwenden',
          'Ähnlichkeit von Dreiecken erkennen und nutzen',
        ],
        typicalOperators: ['berechnen', 'anwenden', 'begründen', 'nachweisen'],
      ),
    ],

    'Gymnasium_9_mathe': const [
      CurriculumTopic(
        competencyArea: 'Funktionaler Zusammenhang',
        topic: 'Quadratische Funktionen und Potenzen',
        learningGoals: [
          'Quadratische Funktionen: Normalform, Scheitelpunktform',
          'Nullstellen mit p-q-Formel/Mitternachtsformel berechnen',
          'Potenzgesetze erweitert (rationale Exponenten, Wurzeln)',
          'Potenzfunktionen untersuchen',
        ],
        typicalOperators: [
          'berechnen',
          'umformen',
          'zeichnen',
          'analysieren',
          'vergleichen',
        ],
      ),
    ],

    'Gymnasium_10_mathe': const [
      CurriculumTopic(
        competencyArea: 'Funktionaler Zusammenhang',
        topic: 'Exponentialfunktionen, Trigonometrie, Stochastik',
        learningGoals: [
          'Exponentialfunktionen und Logarithmus',
          'Trigonometrie: sin, cos, tan im rechtwinkligen Dreieck und Einheitskreis',
          'Sinusfunktion untersuchen (Amplitude, Periode)',
          'Mehrstufige Zufallsexperimente und Baumdiagramme',
          'Bedingte Wahrscheinlichkeit (Grundlagen)',
        ],
        typicalOperators: [
          'berechnen',
          'analysieren',
          'begründen',
          'modellieren',
          'interpretieren',
        ],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // HAUPTSCHULE — DEUTSCH
    // ══════════════════════════════════════════════════════════════════════
    'Hauptschule_7_deutsch': const [
      CurriculumTopic(
        competencyArea: 'Sprache und Sprachgebrauch untersuchen',
        topic: 'Satzglieder und Wortarten festigen',
        learningGoals: [
          'Subjekt, Prädikat, Objekt (Akkusativ, Dativ) bestimmen',
          'Adverbiale Bestimmungen erkennen (Ort, Zeit, Art und Weise)',
          'Satzgefüge und Satzreihe unterscheiden',
          'Aktiv und Passiv in einfachen Sätzen',
        ],
        typicalOperators: [
          'bestimmen',
          'benennen',
          'unterscheiden',
          'umformen',
        ],
        notExpected: ['Konjunktiv II', 'Satzanalyse komplexer Literatur'],
      ),
      CurriculumTopic(
        competencyArea: 'Texte schreiben',
        topic: 'Berichte und Beschreibungen',
        learningGoals: [
          'Unfallberichte / Zeitungsberichte im Präteritum schreiben',
          'Personen- und Vorgangsbeschreibungen verfassen',
          'W-Fragen als Strukturhilfe nutzen',
        ],
        typicalOperators: [
          'schreiben',
          'beschreiben',
          'berichten',
          'strukturieren',
        ],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // REALSCHULE — DEUTSCH
    // ══════════════════════════════════════════════════════════════════════
    'Realschule_7_deutsch': const [
      CurriculumTopic(
        competencyArea: 'Sprache und Sprachgebrauch untersuchen',
        topic: 'Satzglieder, Nebensätze und Aktiv/Passiv',
        learningGoals: [
          'Alle Satzglieder sicher bestimmen (Subjekt, Prädikat, Objekte, Adverbiale)',
          'Nebensatzarten unterscheiden (Relativ-, Konjunktional-, Infinitivsatz)',
          'Aktiv und Passiv sicher umformen und anwenden',
          'Konjunktiv I in der indirekten Rede (Grundlagen)',
        ],
        typicalOperators: [
          'bestimmen',
          'unterscheiden',
          'umformen',
          'erklären',
        ],
        notExpected: [
          'Konjunktiv II in irrealen Bedingungen',
          'Literarische Stilanalyse',
        ],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // GYMNASIUM — DEUTSCH
    // ══════════════════════════════════════════════════════════════════════
    'Gymnasium_7_deutsch': const [
      CurriculumTopic(
        competencyArea: 'Sprache und Sprachgebrauch untersuchen',
        topic: 'Grammatik vertieft und Stilmittel',
        learningGoals: [
          'Satzglieder und Gliedsätze vollständig bestimmen und benennen',
          'Aktiv/Passiv inkl. aller Zeitformen',
          'Konjunktiv I (indirekte Rede) und Konjunktiv II (irreale Bedingungen)',
          'Erste rhetorische Stilmittel erkennen (Metapher, Vergleich, Personifikation)',
          'Sprachliche Mittel in Texten untersuchen und ihre Wirkung beschreiben',
        ],
        typicalOperators: [
          'bestimmen',
          'benennen',
          'erklären',
          'untersuchen',
          'beschreiben',
          'vergleichen',
        ],
        notExpected: ['Epochenzuordnung von Literatur'],
      ),
      CurriculumTopic(
        competencyArea: 'Texte schreiben',
        topic: 'Argumentation und Inhaltsangabe',
        learningGoals: [
          'Begründete Stellungnahmen verfassen (These → Argument → Beispiel)',
          'Inhaltsangaben im Präsens schreiben',
          'Erzählperspektiven erkennen und verwenden',
        ],
        typicalOperators: [
          'verfassen',
          'zusammenfassen',
          'begründen',
          'erklären',
        ],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // HAUPTSCHULE — ENGLISCH
    // ══════════════════════════════════════════════════════════════════════
    'Hauptschule_7_englisch': const [
      CurriculumTopic(
        competencyArea: 'Grammatik und Wortschatz',
        topic: 'Zeitformen und Alltagskommunikation',
        learningGoals: [
          'Simple Present und Simple Past sicher anwenden',
          'Present Progressive vs. Simple Present unterscheiden',
          'Going-to-Future für Pläne und Absichten',
          'Alltagsdialoge: Einkaufen, Wegbeschreibung, Freizeit',
          'Grundwortschatz: ca. 1.200 Wörter',
        ],
        typicalOperators: [
          'ergänzen',
          'zuordnen',
          'bilden',
          'übersetzen',
          'antworten',
        ],
        notExpected: [
          'Past Perfect',
          'Reported Speech',
          'Conditional sentences',
          'Textanalyse',
          'Mediation komplexer Texte',
        ],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // REALSCHULE — ENGLISCH
    // ══════════════════════════════════════════════════════════════════════
    'Realschule_7_englisch': const [
      CurriculumTopic(
        competencyArea: 'Grammatik und Wortschatz',
        topic: 'Erweiterte Zeitformen und Textproduktion',
        learningGoals: [
          'Alle einfachen Zeitformen sicher (Present, Past, Future)',
          'Present Perfect für Erfahrungen und Ergebnisse',
          'Modale Hilfsverben (can, must, should, may)',
          'Vergleichsformen der Adjektive (comparative, superlative)',
          'Kurze Texte schreiben (E-Mail, Tagebucheintrag)',
          'Grundwortschatz: ca. 1.800 Wörter',
        ],
        typicalOperators: [
          'ergänzen',
          'bilden',
          'schreiben',
          'erklären',
          'vergleichen',
        ],
        notExpected: ['Reported Speech', 'Conditional III', 'Textanalyse'],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // GYMNASIUM — ENGLISCH
    // ══════════════════════════════════════════════════════════════════════
    'Gymnasium_7_englisch': const [
      CurriculumTopic(
        competencyArea: 'Grammatik und Sprachkompetenz',
        topic: 'Komplexere Grammatik und Textarbeit',
        learningGoals: [
          'Alle Zeitformen inkl. Past Progressive und Present Perfect Progressive',
          'Conditional sentences Typ I und II (if-clauses)',
          'Relative clauses (defining/non-defining)',
          'Passivkonstruktionen (Simple Present/Past Passive)',
          'Texte zusammenfassen und Stellung nehmen',
          'Grundwortschatz: ca. 2.500 Wörter',
        ],
        typicalOperators: [
          'bilden',
          'umformen',
          'erklären',
          'vergleichen',
          'zusammenfassen',
          'Stellung nehmen',
        ],
        notExpected: ['Reported Speech vertieft', 'Conditional III'],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // NATURWISSENSCHAFTEN (Klasse 5–10)
    // ══════════════════════════════════════════════════════════════════════
    'Gymnasium_7_biologie': const [
      CurriculumTopic(
        competencyArea: 'Evolution und Ökologie',
        topic: 'Evolutionstheorie und Ökosysteme',
        learningGoals: [
          'Darwins Evolutionstheorie: Variation, Selektion, Anpassung',
          'Fossilien als Belege der Evolution',
          'Nahrungsketten und Nahrungsnetze',
          'Produzenten, Konsumenten, Destruenten unterscheiden',
          'Fotosynthese als Grundlage des Lebens (Wortgleichung)',
        ],
        typicalOperators: [
          'beschreiben',
          'erklären',
          'vergleichen',
          'begründen',
          'darstellen',
        ],
      ),
    ],

    'Hauptschule_7_biologie': const [
      CurriculumTopic(
        competencyArea: 'Mensch und Gesundheit',
        topic: 'Ernährung und Verdauung',
        learningGoals: [
          'Nährstoffe benennen (Kohlenhydrate, Fette, Eiweiße, Vitamine)',
          'Verdauungsorgane und ihre Funktion kennen',
          'Gesunde Ernährung: Ernährungspyramide verstehen',
          'Zähne und Zahnpflege',
        ],
        typicalOperators: ['benennen', 'beschreiben', 'zuordnen', 'erklären'],
        notExpected: ['Enzymatische Reaktionen', 'Biochemische Formeln'],
      ),
    ],

    'Gymnasium_7_chemie': const [
      CurriculumTopic(
        competencyArea: 'Stoffe und Reaktionen',
        topic: 'Atombau und chemische Reaktionen',
        learningGoals: [
          'Atommodell von Dalton und Bohr (Schalen)',
          'Element, Verbindung und Gemisch unterscheiden',
          'Chemische Reaktion als Umgruppierung von Atomen',
          'Wortgleichungen aufstellen',
          'Exotherme und endotherme Reaktionen',
          'Periodensystem: Aufbau und Hauptgruppen (Grundlagen)',
        ],
        typicalOperators: [
          'beschreiben',
          'erklären',
          'unterscheiden',
          'aufstellen',
          'begründen',
        ],
      ),
    ],

    'Gymnasium_7_physik': const [
      CurriculumTopic(
        competencyArea: 'Elektrizitätslehre und Optik',
        topic: 'Stromkreise und Optik',
        learningGoals: [
          'Elektrische Stromkreise: Reihen- und Parallelschaltung',
          'Spannung, Stromstärke und Widerstand (qualitativ)',
          'Ohmsches Gesetz (U = R · I)',
          'Lichtausbreitung, Reflexion und Brechung',
          'Bilder an Spiegeln und Linsen',
        ],
        typicalOperators: [
          'beschreiben',
          'erklären',
          'berechnen',
          'zeichnen',
          'untersuchen',
        ],
      ),
    ],

    // ══════════════════════════════════════════════════════════════════════
    // GESCHICHTE
    // ══════════════════════════════════════════════════════════════════════
    'Gymnasium_7_geschichte': const [
      CurriculumTopic(
        competencyArea: 'Mittelalter und Neuzeit',
        topic: 'Mittelalter, Reformation und Entdeckungen',
        learningGoals: [
          'Lehnswesen und Ständegesellschaft im Mittelalter',
          'Leben in der mittelalterlichen Stadt',
          'Martin Luther und die Reformation',
          'Entdeckungsreisen (Kolumbus, Vasco da Gama)',
          'Quellen auswerten: Texte, Bilder, Karten',
        ],
        typicalOperators: [
          'beschreiben',
          'erklären',
          'vergleichen',
          'einordnen',
          'beurteilen (angeleitet)',
        ],
      ),
    ],

    'Hauptschule_7_geschichte': const [
      CurriculumTopic(
        competencyArea: 'Mittelalter',
        topic: 'Leben im Mittelalter',
        learningGoals: [
          'Wie lebten die Menschen im Mittelalter? (Bauern, Ritter, Mönche)',
          'Burgen und Städte im Mittelalter',
          'Grundherrschaft und Leibeigenschaft einfach erklärt',
          'Wichtige Erfindungen (Buchdruck)',
        ],
        typicalOperators: [
          'beschreiben',
          'benennen',
          'erklären (einfach)',
          'zuordnen',
        ],
        notExpected: ['Quellenanalyse', 'Historiographische Debatten'],
      ),
    ],
  };
}
