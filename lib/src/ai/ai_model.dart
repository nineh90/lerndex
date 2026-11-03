import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_ai/firebase_ai.dart';

// ============================================================================
// KI-ZUGANG: DIREKT ODER ÜBER DEN EIGENEN SERVER
//
// Android: Die App spricht Gemini direkt über firebase_ai an (Vertex AI in
// Frankfurt), abgesichert mit App Check (Play Integrity).
// Browser: Die Web-App schickt dieselbe Anfrage an die Cloud Function
// `aiGenerate` (functions/ai.js). Dort liegt der Zugang zu Gemini, im Browser
// gibt es keinen nutzbaren Schlüssel, und es braucht weder App Check noch
// reCAPTCHA. Die Function lässt nur angemeldete Konten zu (mit Tageslimit) und
// legt Modell, Region und Safety-Settings selbst fest.
//
// Beide Wege liefern nur den Antworttext – mehr nutzt die App nicht.
// ============================================================================

/// Antwort eines KI-Aufrufs.
class AiResponse {
  const AiResponse(
    this.text, {
    this.finishReason,
    this.thoughtsTokens,
    this.totalTokens,
  });

  /// Antworttext ohne Denk-Teile; null, wenn das Modell nichts geliefert hat.
  final String? text;

  /// Abschlussgrund wie bei Vertex AI: STOP, MAX_TOKENS, SAFETY, …
  final String? finishReason;
  final int? thoughtsTokens;
  final int? totalTokens;
}

/// Ein KI-Modell mit fester Konfiguration (Systemanweisung, Token-Limit,
/// Antwortformat).
abstract class AiModel {
  Future<AiResponse> generateContent(Iterable<Content> contents);

  /// Gespräch mit bisherigem Verlauf (Tutor).
  AiChat startChat({List<Content> history = const []}) =>
      AiChat._(this, history);
}

/// Gespräch: hängt jede Nachricht und Antwort an den Verlauf an.
class AiChat {
  AiChat._(this._model, List<Content> history) : _history = [...history];

  final AiModel _model;
  final List<Content> _history;

  Future<AiResponse> sendMessage(Content message) async {
    final response = await _model.generateContent([..._history, message]);
    _history
      ..add(message)
      ..add(Content.model([TextPart(response.text ?? '')]));
    return response;
  }
}

/// Direkt über firebase_ai (Android, Tests auf dem Rechner).
class DirectAiModel extends AiModel {
  DirectAiModel(this._model);

  final GenerativeModel _model;

  @override
  Future<AiResponse> generateContent(Iterable<Content> contents) async {
    final r = await _model.generateContent(contents);
    return AiResponse(
      r.text,
      finishReason: r.candidates.firstOrNull?.finishReason?.toJson(),
      thoughtsTokens: r.usageMetadata?.thoughtsTokenCount,
      totalTokens: r.usageMetadata?.totalTokenCount,
    );
  }
}

/// Über die Cloud Function `aiGenerate` (Browser).
class ServerAiModel extends AiModel {
  ServerAiModel({
    required FirebaseFunctions functions,
    required this.generationConfig,
    this.systemInstruction,
    this.timeout = const Duration(seconds: 90),
  }) : _functions = functions; // ignore: prefer_initializing_formals

  final FirebaseFunctions _functions;
  final GenerationConfig generationConfig;
  final Content? systemInstruction;
  final Duration timeout;

  /// Anfrage im JSON-Format von Vertex AI (so schickt sie auch firebase_ai).
  Map<String, Object?> requestBody(Iterable<Content> contents) => {
    'contents': [for (final c in contents) c.toJson()],
    if (systemInstruction case final s?) 'systemInstruction': s.toJson(),
    'generationConfig': generationConfig.toJson(),
  };

  @override
  Future<AiResponse> generateContent(Iterable<Content> contents) async {
    final callable = _functions.httpsCallable(
      'aiGenerate',
      options: HttpsCallableOptions(timeout: timeout),
    );
    try {
      final result = await callable.call(requestBody(contents));
      final data = Map<String, Object?>.from(result.data as Map);
      return AiResponse(
        data['text'] as String?,
        finishReason: data['finishReason'] as String?,
        thoughtsTokens: data['thoughtsTokens'] as int?,
        totalTokens: data['totalTokens'] as int?,
      );
    } on FirebaseFunctionsException catch (e) {
      throw AiServerException(e.code, e.message ?? e.code);
    }
  }
}

/// Fehler der Server-KI (z.B. Tageslimit erreicht, Antwort geblockt).
class AiServerException implements Exception {
  const AiServerException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AiServerException($code): $message';
}
