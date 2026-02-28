import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';
import '../domain/generated_task_result.dart';
import '../../auth/domain/child_model.dart';

/// 🤖 VERBESSERTER FIREBASE AI SERVICE
///
/// Generiert Multiple-Choice-Aufgaben aus hochgeladenen Fotos
/// - 4 Antwortmöglichkeiten pro Frage
/// - Genau 1 richtige Antwort
/// - Optional: Ausführliche Lösungserklärung
/// - Fach-spezifische Prompts

class ImprovedFirebaseAIService {
  GenerativeModel? _taskGeneratorModel;
  bool _isInitialized = false;

  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Initialisiert das AI-Modell
  Future<void> initialize() async {
    if (_isInitialized) {
      print('ℹ️ Firebase AI ist bereits initialisiert');
      return;
    }

    print('🚀 Firebase AI wird initialisiert...');

    try {
      _taskGeneratorModel = FirebaseVertexAI.instance.generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(
          temperature: 0.8,
          maxOutputTokens: 3000,
          topP: 0.95,
        ),
      );

      _isInitialized = true;
      print('✅ Firebase AI initialisiert!');
    } catch (e) {
      print('❌ Fehler bei AI-Initialisierung: $e');
      rethrow;
    }
  }

  // ========================================================================
  // AUFGABENGENERIERUNG AUS FOTOS
  // ========================================================================

  /// Analysiert Foto und generiert Multiple-Choice-Aufgaben
  Future<GeneratedTaskResult> generateTasksFromImage({
    required File imageFile,
    required ChildModel child,
    required String userId,
    required Subject subject,
    int numberOfTasks = 5,
  }) async {
    try {
      if (!_isInitialized) await initialize();

      print(
        '📸 Analysiere Schulaufgabe für ${child.name} (${subject.displayName})...',
      );

      // 1. Bild hochladen zu Firebase Storage (optional – Fehler blockiert nicht die KI-Generierung)
      String? imageUrl;
      try {
        imageUrl = await _uploadImage(imageFile, userId, child.id, subject);
      } catch (uploadError) {
        print('⚠️ Bild-Upload fehlgeschlagen (wird ignoriert): $uploadError');
      }

      // 2. Bild als Bytes lesen
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // 3. System-Prompt für Fach
      final systemPrompt = _getTaskGeneratorPrompt(
        child: child,
        subject: subject,
        numberOfTasks: numberOfTasks,
      );

      // 4. Vision API: Bild + Prompt
      final content = [
        Content.multi([
          TextPart(systemPrompt),
          InlineDataPart('image/jpeg', imageBytes),
        ]),
      ];

      print('🤖 Sende Anfrage an Gemini...');
      final response = await _taskGeneratorModel!.generateContent(content);
      final text = response.text;

      if (text == null || text.isEmpty) {
        throw Exception('KI hat keine Antwort generiert');
      }

      print('📝 Antwort erhalten, parse JSON...');

      // 5. Parse JSON zu GeneratedQuestion-Objekten
      final questions = _parseGeneratedQuestions(text);

      if (questions.isEmpty) {
        throw Exception('Keine validen Aufgaben generiert');
      }

      print('✅ ${questions.length} Aufgaben erfolgreich generiert!');

      return GeneratedTaskResult(
        success: true,
        questions: questions,
        imageUrl: imageUrl,
      );
    } catch (e) {
      print('❌ Fehler bei Aufgabengenerierung: $e');
      return GeneratedTaskResult(
        success: false,
        questions: [],
        errorMessage: e.toString(),
      );
    }
  }

  // ========================================================================
  // HILFSMETHODEN
  // ========================================================================

  /// System-Prompt für Aufgabengenerierung (fachspezifisch)
  String _getTaskGeneratorPrompt({
    required ChildModel child,
    required Subject subject,
    required int numberOfTasks,
  }) {
    final subjectContext = _getSubjectContext(subject);

    return '''
Du bist ein pädagogischer Experte, der personalisierte Übungsaufgaben für Schüler erstellt.

SCHÜLER-INFORMATIONEN:
- Name: ${child.name}
- Alter: ${child.age} Jahre
- Klassenstufe: ${child.grade}
- Schulform: ${child.schoolType}
- Fach: ${subject.displayName}

$subjectContext

AUFGABE:
Analysiere das hochgeladene Foto einer Schulaufgabe und erstelle $numberOfTasks ähnliche Multiple-Choice-Übungsaufgaben.

ANFORDERUNGEN:
1. Analysiere Thema, Schwierigkeitsniveau und Stil der Vorlage
2. Erstelle $numberOfTasks neue, ähnliche Aufgaben (NICHT identisch!)
3. Jede Aufgabe muss EXAKT 4 Antwortmöglichkeiten haben
4. GENAU 1 Antwort muss korrekt sein, 3 müssen plausible Ablenkungen sein
5. Schwierigkeit muss für Klasse ${child.grade} passend sein
6. Gib bei jeder Aufgabe eine ausführliche Lösungserklärung an

WICHTIG - MULTIPLE-CHOICE-REGELN:
- Die Antwortmöglichkeiten müssen sich deutlich unterscheiden
- Falsche Antworten müssen plausibel klingen (keine offensichtlichen Ablenkungen)
- Alle 4 Optionen sollten ähnlich lang sein
- Vermeide "alle oben genannten" oder "keine der oben genannten"

FORMAT:
Gib deine Antwort als JSON-Array zurück:

[
  {
    "question": "Die Aufgabenstellung als klare Frage",
    "options": [
      "Antwortmöglichkeit 1",
      "Antwortmöglichkeit 2",
      "Antwortmöglichkeit 3",
      "Antwortmöglichkeit 4"
    ],
    "correctAnswer": "Die exakte richtige Antwort (muss identisch mit einer Option sein)",
    "solution": "Ausführliche Erklärung, warum diese Antwort richtig ist und wie man zur Lösung kommt",
    "difficulty": "easy|medium|hard",
    "topic": "Spezifisches Thema (z.B. 'Bruchrechnung', 'Wortarten', 'Simple Past')"
  }
]

BEISPIELE FÜR GUTE MULTIPLE-CHOICE-AUFGABEN:

Mathematik Klasse 5:
{
  "question": "Was ist 3/4 + 1/4?",
  "options": ["1/2", "4/8", "1", "4/4"],
  "correctAnswer": "1",
  "solution": "Wenn beide Brüche den gleichen Nenner haben, addiert man nur die Zähler: 3/4 + 1/4 = (3+1)/4 = 4/4 = 1",
  "difficulty": "easy",
  "topic": "Bruchrechnung - Addition"
}

Deutsch Klasse 4:
{
  "question": "Welches Wort ist ein Adjektiv?",
  "options": ["laufen", "schnell", "Haus", "gestern"],
  "correctAnswer": "schnell",
  "solution": "Ein Adjektiv beschreibt, wie etwas ist (Wie-Wort). 'Schnell' beschreibt eine Eigenschaft und ist daher ein Adjektiv. 'Laufen' ist ein Verb, 'Haus' ein Nomen und 'gestern' ein Adverb.",
  "difficulty": "medium",
  "topic": "Wortarten"
}

QUALITÄTSKRITERIEN:
✓ Aufgaben sind ähnlich zur Vorlage, aber NICHT identisch
✓ Zahlen, Wörter oder Kontext wurden variiert
✓ Schwierigkeit ist altersgerecht
✓ Alle Aufgaben sind lösbar und sinnvoll
✓ Lösungserklärungen sind verständlich und lehrreich
✓ Jede Frage hat EXAKT 4 Optionen und 1 korrekte Antwort

Gib NUR das JSON-Array zurück, ohne zusätzlichen Text!
''';
  }

  /// Fach-spezifischer Kontext
  String _getSubjectContext(Subject subject) {
    switch (subject) {
      case Subject.mathe:
        return '''
FACH: MATHEMATIK
Typische Themen je Klassenstufe:
- Klasse 1-2: Grundrechenarten, Zahlenraum bis 100
- Klasse 3-4: Multiplikation, Division, Textaufgaben, Geometrie
- Klasse 5-6: Bruchrechnung, Dezimalzahlen, Prozentrechnung
- Klasse 7-8: Algebra, Gleichungen, Geometrie
- Klasse 9-10: Funktionen, Trigonometrie, Stochastik

Achte auf mathematische Korrektheit und eindeutige Lösungswege!
''';

      case Subject.deutsch:
        return '''
FACH: DEUTSCH
Typische Themen je Klassenstufe:
- Klasse 1-2: Buchstaben, Silben, einfache Wörter
- Klasse 3-4: Rechtschreibung, Wortarten, Satzglieder, Aufsätze
- Klasse 5-6: Grammatik, Zeitformen, direkte/indirekte Rede
- Klasse 7-8: Textanalyse, Argumentation, Stilmittel
- Klasse 9-10: Interpretation, Erörterung, Literaturanalyse

Achte auf sprachliche Korrektheit und altersgerechte Formulierungen!
''';

      case Subject.englisch:
        return '''
FACH: ENGLISCH
Typische Themen je Klassenstufe:
- Klasse 3-4: Grundwortschatz, einfache Sätze, Zahlen, Farben
- Klasse 5-6: Simple Present/Past, Vokabeln, Dialoge
- Klasse 7-8: Zeitformen, if-clauses, Textverständnis
- Klasse 9-10: Reported Speech, Passive Voice, Textanalyse

Achte auf grammatikalische Korrektheit und authentisches Englisch!
Verwende britisches oder amerikanisches Englisch konsistent!
''';

      case Subject.sachkunde:
        return '''
FACH: SACHKUNDE / NATURWISSENSCHAFTEN
Typische Themen je Klassenstufe:
- Klasse 1-2: Jahreszeiten, Tiere, Pflanzen, Verkehr
- Klasse 3-4: Wasser, Strom, Magnetismus, Körper, Umwelt
- Klasse 5-6: Biologie (Zellen, Ökosysteme), Physik (Kräfte), Chemie (Stoffe)
- Klasse 7-8: Evolution, Elektrizität, chemische Reaktionen
- Klasse 9-10: Genetik, Energie, Periodensystem

Achte auf wissenschaftliche Korrektheit und altersgerechte Erklärungen!
''';

      case Subject.biologie:
        return '''
FACH: BIOLOGIE
Typische Themen je Klassenstufe:
- Klasse 5-6: Zellen, Pflanzen, Tiere, Ökosysteme
- Klasse 7-8: Genetik, Evolution, menschlicher Körper
- Klasse 9-10: Fortpflanzung, Neurobiologie, Ökologie
- Klasse 11-13: Molekularbiologie, Genetik, Biochemie

Achte auf biologische Fachbegriffe und wissenschaftliche Korrektheit!
''';

      case Subject.chemie:
        return '''
FACH: CHEMIE
Typische Themen je Klassenstufe:
- Klasse 5-6: Stoffe und ihre Eigenschaften, Trennverfahren
- Klasse 7-8: Atombau, chemische Bindungen, Reaktionen
- Klasse 9-10: Säuren, Basen, Salze, Oxidation
- Klasse 11-13: Organische Chemie, Elektrochemie, Reaktionskinetik

Achte auf chemische Fachbegriffe und korrekte Formeln!
''';

      case Subject.physik:
        return '''
FACH: PHYSIK
Typische Themen je Klassenstufe:
- Klasse 5-6: Mechanik, Kräfte, einfache Maschinen
- Klasse 7-8: Elektrizität, Magnetismus, Optik
- Klasse 9-10: Wellen, Energie, Wärmelehre
- Klasse 11-13: Quantenphysik, Relativitätstheorie, Atomphysik

Achte auf physikalische Einheiten und Formeln!
''';

      case Subject.geschichte:
        return '''
FACH: GESCHICHTE
Typische Themen je Klassenstufe:
- Klasse 5-6: Antike, Ägypten, Griechen, Römer
- Klasse 7-8: Mittelalter, Neuzeit, Reformation
- Klasse 9-10: Industrialisierung, Weltkriege, Weimarer Republik
- Klasse 11-13: NS-Zeit, Kalter Krieg, Zeitgeschichte

Achte auf historische Fakten und zeitliche Einordnung!
''';
    }
  }

  /// Lädt Bild zu Firebase Storage hoch
  Future<String> _uploadImage(
    File imageFile,
    String userId,
    String childId,
    Subject subject,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'task_images/$userId/$childId/${subject.value}/$timestamp.jpg';

    final ref = _storage.ref().child(path);
    await ref.putFile(imageFile);

    final url = await ref.getDownloadURL();
    print('✅ Bild hochgeladen: $path');
    return url;
  }

  /// Parst generierte Aufgaben aus AI-Response
  List<GeneratedQuestion> _parseGeneratedQuestions(String jsonText) {
    try {
      // Entferne Markdown-Formatierung
      String cleaned = jsonText.trim();

      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }

      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }

      cleaned = cleaned.trim();

      // Parse JSON
      final List<dynamic> jsonList = jsonDecode(cleaned);

      final questions = <GeneratedQuestion>[];

      for (var json in jsonList) {
        try {
          // Validierung
          if (json['question'] == null || json['question'].toString().isEmpty) {
            print('⚠️ Überspringe Aufgabe ohne Frage');
            continue;
          }

          if (json['options'] == null ||
              (json['options'] as List).length != 4) {
            print('⚠️ Überspringe Aufgabe: Nicht genau 4 Optionen');
            continue;
          }

          final options = List<String>.from(json['options']);
          final correctAnswer = json['correctAnswer']?.toString() ?? '';

          // Prüfe ob correctAnswer in options vorhanden ist
          if (!options.contains(correctAnswer)) {
            print('⚠️ Überspringe Aufgabe: Richtige Antwort nicht in Optionen');
            continue;
          }

          questions.add(
            GeneratedQuestion(
              id: '', // Wird beim Speichern gesetzt
              question: json['question'].toString(),
              options: options,
              correctAnswer: correctAnswer,
              solution: json['solution']?.toString(),
              difficulty: json['difficulty']?.toString() ?? 'medium',
              topic: json['topic']?.toString() ?? '',
              status: TaskApprovalStatus.pending,
              createdAt: DateTime.now(),
            ),
          );
        } catch (e) {
          print('⚠️ Fehler beim Parsen einer Aufgabe: $e');
          continue;
        }
      }

      return questions;
    } catch (e) {
      print('❌ JSON Parse Fehler: $e');
      print('Text war: $jsonText');
      return [];
    }
  }
}

// ========================================================================
// RIVERPOD PROVIDER
// ========================================================================

final improvedFirebaseAIServiceProvider = Provider<ImprovedFirebaseAIService>((
  ref,
) {
  final service = ImprovedFirebaseAIService();
  service.initialize();
  return service;
});
