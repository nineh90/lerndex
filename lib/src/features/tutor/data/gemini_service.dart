import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../domain/chat_message.dart';
import '../domain/tutor_config.dart';
import '../../auth/domain/child_model.dart';

/// Service für Kommunikation mit Google Gemini API
class GeminiService {
  late final GenerativeModel _model;
  late final String _systemPrompt;

  /// Initialisiert den Gemini Service
  /// WICHTIG: Muss VOR Nutzung aufgerufen werden!
  Future<void> initialize(ChildModel child) async {
    print('🚀 Starte Tutor-Initialisierung...');

    if (!dotenv.isInitialized) {
      await dotenv.load(fileName: '.env');
    }

    final apiKey = dotenv.env['GEMINI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY nicht in .env gefunden!');
    }

    print('🔑 API-Key geladen');

    // TESTE ALLE MÖGLICHEN MODELLE
    final modelsToTry = [
      'gemini-1.5-flash',
      'gemini-1.0-pro',
      'gemini-pro',
      'models/gemini-1.5-flash',
      'models/gemini-pro',
    ];

    GenerativeModel? workingModel;
    String? workingModelName;

    for (var modelName in modelsToTry) {
      try {
        print('🧪 Teste Modell: $modelName');

        final testModel = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
        );

        // Kurzer Test
        final response = await testModel.generateContent([
          Content.text('Hallo')
        ]);

        if (response.text != null && response.text!.isNotEmpty) {
          print('✅ ERFOLG! Modell funktioniert: $modelName');
          workingModel = testModel;
          workingModelName = modelName;
          break;
        }
      } catch (e) {
        print('❌ Fehler bei $modelName: ${e.toString().substring(0, 100)}...');
      }
    }

    if (workingModel == null) {
      throw Exception('❌ Kein funktionierendes Modell gefunden! Prüfe deinen API-Key!');
    }

    print('🎉 Verwende Modell: $workingModelName');

    _systemPrompt = TutorConfig.getSystemPrompt(child);

    // Verwende das funktionierende Modell mit allen Settings
    _model = GenerativeModel(
      model: workingModelName!,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 500,
        topP: 0.9,
        topK: 40,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
      ],
    );

    print('✅ Tutor komplett initialisiert!');
  }

  /// Sendet eine Nachricht an Gemini und bekommt Antwort
  Future<String> sendMessage(
      String userMessage,
      List<ChatMessage> conversationHistory,
      ) async {
    try {
      // Sicherheitscheck
      if (!TutorConfig.isAppropriateQuestion(userMessage)) {
        return TutorConfig.inappropriateQuestionMessage;
      }

      // Längencheck
      if (userMessage.length > TutorConfig.maxMessageLength) {
        return 'Deine Frage ist etwas zu lang. Kannst du sie kürzer formulieren? 😊';
      }

      // Chat-Session erstellen mit Kontext
      final history = _buildHistory(conversationHistory);

      // Füge System-Prompt als erste Nachricht hinzu, wenn Chat leer
      if (conversationHistory.isEmpty) {
        history.insert(0, Content.text(_systemPrompt));
      }

      final chat = _model.startChat(history: history);

      // Nachricht senden
      final response = await chat.sendMessage(
        Content.text(userMessage),
      );

      // Antwort extrahieren
      final text = response.text;

      if (text == null || text.isEmpty) {
        return 'Hmm, ich bin mir bei dieser Frage nicht sicher. Kannst du sie anders formulieren? 🤔';
      }

      return text;
    } catch (e) {
      print('Gemini API Fehler: $e');

      // Benutzerfreundliche Fehlermeldung
      if (e.toString().contains('API key')) {
        return 'Es gibt ein Problem mit der Verbindung. Bitte informiere deine Eltern! 🔧';
      }

      return 'Ups, da ist etwas schiefgelaufen. Versuch es nochmal! 😅';
    }
  }

  /// Baut die Chat-History für Gemini API
  List<Content> _buildHistory(List<ChatMessage> messages) {
    // Nimm nur die letzten X Nachrichten (für Kontext)
    final recentMessages = messages.length > TutorConfig.contextMessageCount
        ? messages.sublist(messages.length - TutorConfig.contextMessageCount)
        : messages;

    final history = <Content>[];

    for (var message in recentMessages) {
      if (message.isLoading) continue; // Überspringe Lade-Nachrichten

      history.add(
        Content(
          message.isUser ? 'user' : 'model',
          [TextPart(message.text)],
        ),
      );
    }

    return history;
  }

  /// Generiert Lernfragen für ein Thema
  Future<List<String>> generateQuestions({
    required String subject,
    required int grade,
    required int count,
  }) async {
    try {
      final prompt = '''
Erstelle $count Übungsfragen für das Fach $subject, passend für Klasse $grade.

ANFORDERUNGEN:
- Altersgerechte Fragen
- Unterschiedliche Schwierigkeitsgrade
- Kurz und prägnant formuliert
- Keine Multiple-Choice, nur offene Fragen

FORMAT:
Gib die Fragen als nummerierte Liste zurück, eine Frage pro Zeile.

Beispiel:
1. Was ist 5 + 3?
2. Erkläre, was ein Nomen ist.
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text;

      if (text == null || text.isEmpty) return [];

      // Parse Fragen (sehr einfach - kann verbessert werden)
      final questions = <String>[];
      final lines = text.split('\n');

      for (var line in lines) {
        final trimmed = line.trim();
        // Entferne Nummerierung (1. 2. etc.)
        if (trimmed.isEmpty) continue;

        final questionText = trimmed.replaceFirst(RegExp(r'^\d+\.\s*'), '');
        if (questionText.isNotEmpty && questionText != trimmed) {
          questions.add(questionText);
        }
      }

      return questions.take(count).toList();
    } catch (e) {
      print('Fehler beim Generieren von Fragen: $e');
      return [];
    }
  }
}