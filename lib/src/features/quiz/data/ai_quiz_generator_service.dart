import 'dart:convert';
import 'dart:math';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/domain/question_model.dart';
import 'curriculum_data.dart';

/// 🤖 AI QUIZ GENERATOR SERVICE v2.2
///
/// Verbesserungen v2.2:
///   - Anti-Duplikat ueber Topic-Liste statt voller Fragen-Texte (Token-effizient)
///   - Themen-Rotation + Zufalls-Seed sorgen fuer Variation
///   - Kein Kontextproblem bei tausenden gespielten Fragen
class AiQuizGeneratorService {
  GenerativeModel? _model;
  bool _isInitialized = false;
  final _random = Random();

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    _model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-3-flash-preview',
      generationConfig: GenerationConfig(
        temperature: 0.75,
        maxOutputTokens: 4096, // 10 MC-Fragen brauchen ~2000 Tokens
        topP: 0.92,
        responseMimeType: 'application/json',
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high, null),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high, null),
        SafetySetting(
          HarmCategory.sexuallyExplicit,
          HarmBlockThreshold.high,
          null,
        ),
        SafetySetting(
          HarmCategory.dangerousContent,
          HarmBlockThreshold.high,
          null,
        ),
      ],
    );
    _isInitialized = true;
  }

  /// Generiert [count] Fragen fuer ein Kind in einem Fach.
  ///
  /// [recentTopics] — Liste der Topics die kuerzlich dran waren (z.B. ["Prozentrechnung", "Brueche"]).
  ///   Leichtgewichtig: nur Topic-Strings, keine vollen Fragen. Token-effizient auch bei 1000en gespielten Fragen.
  Future<List<Question>> generateQuestions({
    required ChildModel child,
    required String subject,
    int count = 10,
    List<String> recentTopics = const [],
  }) async {
    try {
      await _ensureInitialized();

      final prompt = _buildPrompt(
        child: child,
        subject: subject,
        count: count,
        recentTopics: recentTopics,
      );

      print(
        '📚 Generiere $count Fragen fuer ${child.name} '
        '(${child.schoolType}, Klasse ${child.grade}, Level ${child.level}) '
        'im Fach $subject',
      );

      final response = await _model!.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      return _parseResponse(text, child.grade);
    } catch (e) {
      print('❌ AiQuizGeneratorService: Fehler bei Generierung: $e');
      return [];
    }
  }

  // ======================================================================
  // PROMPT-BUILDING
  // ======================================================================

  String _buildPrompt({
    required ChildModel child,
    required String subject,
    required int count,
    required List<String> recentTopics,
  }) {
    final subjectDisplay = _subjectDisplayName(subject);

    final curriculumContext = CurriculumData.buildCurriculumContext(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject,
      level: child.level,
    );

    final profile = CurriculumData.getDifficultyProfile(
      schoolType: child.schoolType,
      level: child.level,
    );

    final topicFocus = _pickTopicFocus(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject,
      level: child.level,
    );

    final contextSeed = _generateContextSeed(child.grade);

    // Leichtgewichtiger Anti-Duplikat Block: nur Topics, nicht volle Fragen
    final topicAvoidance = recentTopics.isNotEmpty
        ? 'THEMEN-VARIATION:\n'
              'Das Kind hatte kuerzlich viele Fragen zu: ${recentTopics.join(", ")}.\n'
              'Bevorzuge ANDERE Unterthemen und Aufgabentypen innerhalb des Lehrplans.\n'
              'Gleiche Themengebiete sind okay, aber mit anderen Fragestellungen und Zahlen!\n'
        : '';

    final gesamtschulNote = child.schoolType == 'Gesamtschule'
        ? '\nWICHTIG - GESAMTSCHULE:\n'
              'Basierend auf Level ${child.level}: '
              '${child.level <= 4
                  ? "G-Kurs (Grundkurs = Hauptschulniveau)"
                  : child.level <= 8
                  ? "E-Kurs (Erweiterungskurs = Realschulniveau)"
                  : "Oberer E-Kurs (= Gymnasialniveau)"}.\n'
        : '';

    final exampleQuestions = _getExampleQuestions(
      subject: subject,
      schoolType: child.schoolType,
      grade: child.grade,
      level: child.level,
    );

    return '''
Du bist ein hochspezialisierter Aufgabengenerator fuer das deutsche Schulsystem.
Deine Aufgaben basieren auf den offiziellen KMK-Bildungsstandards und Landeslehrplaenen.

SCHUELER-PROFIL:
- Name: ${child.name}
- Alter: ${child.age} Jahre
- Schulform: ${child.schoolType}
- Klasse: ${child.grade}
- App-Level: ${child.level}
- Fach: $subjectDisplay
$gesamtschulNote

LEHRPLAN-KONTEXT:
$curriculumContext

THEMEN-FOKUS FUER DIESEN BATCH:
$topicFocus

$topicAvoidance

VARIATIONSANWEISUNG:
Verwende abwechslungsreiche Kontexte aus dem Alltag des Schuelers.
Kontext-Ideen (nutze VERSCHIEDENE davon):
$contextSeed

WICHTIG FUER ABWECHSLUNG:
- Unterschiedliche Zahlen und Zahlenbereiche bei Rechenaufgaben
- Variiere Fragestellungen (nicht immer "Was ist...?" oder "Berechne...")
- Mische Aufgabentypen (direkte Berechnung, Textaufgabe, Zuordnung, Lueckentext)
- Richtige Antwort ZUFAELLIG auf Position 1, 2, 3 oder 4 verteilen
- Verschiedene Operatoren: ${profile.allowedOperators.join(", ")}

AUFGABE:
Generiere genau $count Multiple-Choice-Fragen fuer "$subjectDisplay".

SCHWIERIGKEITSVERTEILUNG:
- ca. ${(profile.easyRatio * count).round()} leicht (AFB I: Reproduzieren)
- ca. ${(profile.mediumRatio * count).round()} mittel (AFB II: Transfer)
- ca. ${(profile.hardRatio * count).round()} schwer (AFB III: Reflexion)

KRITISCHE REGELN:
${_buildNiveauRules(child.schoolType, child.grade, child.level, subject)}

FORMAT - NUR JSON-Array:
[
  {
    "question": "Aufgabenstellung",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "answer": "Richtige Antwort (identisch mit einer Option)",
    "difficulty": "easy|medium|hard",
    "topic": "Spezifisches Thema"
  }
]

QUALITAETSREGELN:
- Genau 4 Antwortmoeglichkeiten, genau 1 richtige
- Falsche Antworten = typische Schuelerfehler (plausible Distraktoren)
- Alle Optionen aehnlich lang
- Alle Fragen auf Deutsch (ausser bei Englisch als Fach)
- JEDE Frage muss EINZIGARTIG sein - keine inhaltlichen Duplikate!

$exampleQuestions
''';
  }

  // -- THEMEN-ROTATION --

  String _pickTopicFocus({
    required String schoolType,
    required int grade,
    required String subject,
    required int level,
  }) {
    final topics = CurriculumData.getTopics(
      schoolType: schoolType,
      grade: grade,
      subject: subject,
      level: level,
    );

    if (topics.isEmpty) {
      return 'Generiere abwechslungsreiche Fragen zum Fach $subject fuer Klasse $grade.';
    }

    final shuffled = List<CurriculumTopic>.from(topics)..shuffle(_random);
    final focusTopics = shuffled.take(min(2, shuffled.length));

    final buffer = StringBuffer();
    buffer.writeln('Fokussiere diesen Batch auf folgende Themen:');
    for (final topic in focusTopics) {
      buffer.writeln('  * ${topic.topic}');
      final goals = List<String>.from(topic.learningGoals)..shuffle(_random);
      for (final goal in goals.take(min(3, goals.length))) {
        buffer.writeln('    -> $goal');
      }
    }

    if (topics.length > 2) {
      buffer.writeln();
      buffer.writeln('1-2 Fragen duerfen auch aus anderen Themen kommen:');
      for (final topic in topics.where((t) => !focusTopics.contains(t))) {
        buffer.writeln('  - ${topic.topic}');
      }
    }

    return buffer.toString();
  }

  // -- KONTEXT-SEED --

  String _generateContextSeed(int grade) {
    final names = [
      'Mia',
      'Leon',
      'Emma',
      'Noah',
      'Lina',
      'Elias',
      'Sophia',
      'Ben',
      'Hannah',
      'Luis',
      'Marie',
      'Paul',
      'Lea',
      'Finn',
      'Anna',
      'Jonas',
      'Emilia',
      'Lukas',
      'Lara',
      'Maximilian',
      'Clara',
      'Felix',
      'Amelie',
      'Tim',
      'Nele',
      'David',
      'Sophie',
      'Jan',
    ];

    final youngContexts = [
      'Geburtstagsparty',
      'Schulausflug zum Zoo',
      'Schwimmbadbesuch',
      'Bastelnachmittag',
      'Fahrradtour',
      'Buchvorstellung in der Klasse',
      'Waldwanderung',
      'Sportfest',
      'Flohmarkt auf dem Schulhof',
      'Besuch bei Oma und Opa',
      'Spielplatz',
      'Klassenfest',
      'Erntefest',
      'Laternenumzug',
      'Projektwoche',
    ];

    final olderContexts = [
      'Klassenfahrt nach Berlin',
      'Praktikum im Betrieb',
      'Schuelerfirma',
      'Ferienjob im Supermarkt',
      'Handyvertrag vergleichen',
      'Fahrkarten fuer die Bahn',
      'Sportverein-Mitgliedschaft',
      'Renovierung des Jugendzimmers',
      'Taschengeld-Planung',
      'Online-Shopping mit Versandkosten',
      'Kinobesuch mit Freunden',
      'Streaming-Abo vergleichen',
      'Energie und Stromverbrauch',
      'Schulcafeteria betreiben',
      'Spendenaktion organisieren',
    ];

    final contexts = grade <= 6 ? youngContexts : olderContexts;
    final shuffledNames = List<String>.from(names)..shuffle(_random);
    final shuffledContexts = List<String>.from(contexts)..shuffle(_random);

    return 'Namen: ${shuffledNames.take(5).join(", ")}\n'
        'Situationen: ${shuffledContexts.take(4).join(", ")}\n'
        'Zufallszahlen: ${_random.nextInt(90) + 10}, '
        '${_random.nextInt(900) + 100}, ${_random.nextDouble().toStringAsFixed(2)}, '
        '${_random.nextInt(50) + 1}%';
  }

  // -- NIVEAU-REGELN --

  String _buildNiveauRules(
    String schoolType,
    int grade,
    int level,
    String subject,
  ) {
    final topics = CurriculumData.getTopics(
      schoolType: schoolType,
      grade: grade,
      subject: subject,
      level: level,
    );

    final buffer = StringBuffer();
    final allNotExpected = topics.expand((t) => t.notExpected).toSet().toList();

    if (allNotExpected.isNotEmpty) {
      buffer.writeln('DIESE THEMEN SIND ZU SCHWER - NICHT VERWENDEN:');
      for (final ne in allNotExpected) {
        buffer.writeln('   - $ne');
      }
      buffer.writeln();
    }

    switch (schoolType) {
      case 'Hauptschule':
        buffer.writeln('HAUPTSCHULE-NIVEAU:');
        buffer.writeln('   - Starker Alltagsbezug, einfache Formulierungen');
        buffer.writeln('   - Keine Abstraktion, keine formalen Beweise');
        break;
      case 'Realschule':
        buffer.writeln('REALSCHULE-NIVEAU:');
        buffer.writeln('   - Anwendungsorientiert, moderate Fachsprache');
        buffer.writeln('   - Transfer in leicht neue Kontexte');
        break;
      case 'Gymnasium':
        buffer.writeln('GYMNASIUM-NIVEAU:');
        buffer.writeln('   - Fachsprachlich praezise, Transferanforderungen');
        buffer.writeln('   - Bei hoeheren Leveln: Beweisideen, Modellierung');
        break;
      case 'Gesamtschule':
        if (level <= 4) {
          buffer.writeln('GESAMTSCHULE G-KURS: Wie Hauptschule');
        } else if (level <= 8) {
          buffer.writeln('GESAMTSCHULE E-KURS: Wie Realschule');
        } else {
          buffer.writeln('GESAMTSCHULE OBERER E-KURS: Wie Gymnasium');
        }
        break;
      case 'Grundschule':
        buffer.writeln('GRUNDSCHULE:');
        buffer.writeln('   - Kindgerechte Sprache, anschauliche Beispiele');
        buffer.writeln(
          '   - Zahlenraum: ${grade <= 1
              ? "bis 20"
              : grade == 2
              ? "bis 100"
              : grade == 3
              ? "bis 1.000"
              : "bis 1.000.000"}',
        );
        break;
    }

    return buffer.toString();
  }

  // -- BEISPIELFRAGEN --

  String _getExampleQuestions({
    required String subject,
    required String schoolType,
    required int grade,
    required int level,
  }) {
    if (subject.toLowerCase() != 'mathe') return '';

    final String example;
    if (grade <= 4) {
      example =
          '{"question":"Tom hat 36 Murmeln. Er verschenkt ein Viertel. Wie viele behaelt er?","options":["24","27","9","30"],"answer":"27","difficulty":"medium","topic":"Division als Teilen"}';
    } else if (schoolType == 'Hauptschule' ||
        (schoolType == 'Gesamtschule' && level <= 4)) {
      example =
          '{"question":"Ein Fahrrad kostet 280 Euro. Im Sale gibt es 15% Rabatt. Wie viel spart man?","options":["28 Euro","42 Euro","56 Euro","35 Euro"],"answer":"42 Euro","difficulty":"medium","topic":"Prozentrechnung im Alltag"}';
    } else if (schoolType == 'Gymnasium' ||
        (schoolType == 'Gesamtschule' && level > 8)) {
      example =
          '{"question":"Fuer welchen Wert von x gilt: 2(x - 3) + 4 = 3x - 5?","options":["x = 3","x = -3","x = 1","x = 5"],"answer":"x = 3","difficulty":"medium","topic":"Lineare Gleichungen"}';
    } else {
      example =
          '{"question":"Welche Zuordnung ist antiproportional?","options":["Mehr Arbeiter -> weniger Tage","Mehr Aepfel -> hoeherer Preis","Mehr Strecke -> mehr Benzin","Mehr Monate -> mehr Gehalt"],"answer":"Mehr Arbeiter -> weniger Tage","difficulty":"medium","topic":"Zuordnungen"}';
    }

    return 'BEISPIEL:\n[$example]';
  }

  // ======================================================================
  // HILFSMETHODEN
  // ======================================================================

  String _subjectDisplayName(String subject) {
    switch (subject.toLowerCase()) {
      case 'mathe':
        return 'Mathematik';
      case 'deutsch':
        return 'Deutsch';
      case 'englisch':
        return 'Englisch';
      case 'sachkunde':
        return 'Sachkunde / Heimat- und Sachunterricht';
      case 'biologie':
        return 'Biologie';
      case 'chemie':
        return 'Chemie';
      case 'physik':
        return 'Physik';
      case 'geschichte':
        return 'Geschichte';
      default:
        return subject;
    }
  }

  // ======================================================================
  // JSON PARSING
  // ======================================================================

  List<Question> _parseResponse(String rawText, int grade) {
    try {
      final cleaned = rawText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final startIndex = cleaned.indexOf('[');
      final endIndex = cleaned.lastIndexOf(']');
      if (startIndex == -1 || endIndex == -1) {
        print('⚠️ AiQuizGeneratorService: Kein JSON-Array gefunden');
        return [];
      }

      final jsonStr = cleaned.substring(startIndex, endIndex + 1);
      final List<dynamic> jsonList = json.decode(jsonStr);

      final questions = <Question>[];
      final seenQuestions = <String>{};

      for (final item in jsonList) {
        try {
          final q = _parseQuestion(item, grade);
          if (q == null) continue;

          final normalized = q.question.toLowerCase().trim();
          if (seenQuestions.contains(normalized)) {
            print('⚠️ Duplikat innerhalb Batch uebersprungen');
            continue;
          }
          seenQuestions.add(normalized);
          questions.add(q);
        } catch (e) {
          print('⚠️ AiQuizGeneratorService: Frage uebersprungen: $e');
        }
      }

      print(
        '✅ AiQuizGeneratorService: ${questions.length} einzigartige Fragen generiert',
      );
      return questions;
    } catch (e) {
      print('❌ AiQuizGeneratorService: JSON-Parsing fehlgeschlagen: $e');
      return [];
    }
  }

  Question? _parseQuestion(Map<String, dynamic> item, int grade) {
    final question = item['question'] as String? ?? '';
    final options = (item['options'] as List?)?.cast<String>() ?? [];
    final answer = item['answer'] as String? ?? '';
    final difficulty = item['difficulty'] as String? ?? 'medium';
    final topic = item['topic'] as String? ?? '';

    if (question.isEmpty || options.length != 4 || answer.isEmpty) return null;
    if (!options.contains(answer)) return null;

    return Question(
      grade: grade,
      question: question,
      options: options,
      answer: answer,
      difficulty: difficulty,
      topic: topic,
    );
  }
}

// -- Provider --

final aiQuizGeneratorServiceProvider = Provider<AiQuizGeneratorService>((ref) {
  return AiQuizGeneratorService();
});
