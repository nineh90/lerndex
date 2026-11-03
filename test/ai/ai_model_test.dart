import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/ai/ai_model.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';

class _FakeFunctions extends Fake implements FirebaseFunctions {}

void main() {
  test('Server-Anfrage im Vertex-Format: Text, Bild, System, Denk-Stufe', () {
    final model = ServerAiModel(
      functions: _FakeFunctions(),
      generationConfig: VertexAIService.generationConfig(
        maxOutputTokens: 1024,
        responseMimeType: 'application/json',
        responseSchema: VertexAIService.drawingCheckSchema,
      ),
      systemInstruction: Content.system('Du bist Lexi.'),
    );
    final body = model.requestBody([
      Content('user', [TextPart('Hallo')]),
      Content('model', [TextPart('Hi!')]),
      Content.multi([
        TextPart('Was ist das?'),
        InlineDataPart('image/png', Uint8List.fromList([1, 2, 3])),
      ]),
    ]);
    // Muss als JSON serialisierbar sein (so geht es über die Callable)
    final json = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;

    final contents = json['contents'] as List;
    expect(contents, hasLength(3));
    expect(contents[0], {
      'role': 'user',
      'parts': [
        {'text': 'Hallo'},
      ],
    });
    final image = (contents[2]['parts'] as List)[1] as Map;
    expect(image['inlineData'], {'mimeType': 'image/png', 'data': 'AQID'});

    expect(json['systemInstruction']['parts'][0]['text'], 'Du bist Lexi.');
    final config = json['generationConfig'] as Map;
    expect(config['maxOutputTokens'], 1024);
    expect(config['responseMimeType'], 'application/json');
    expect(config['thinkingConfig'], {'thinkingLevel': 'LOW'});
    expect(config['responseSchema']['type'], 'OBJECT');
  });

  test('Gespräch hängt Nachricht und Antwort an den Verlauf', () async {
    final seen = <int>[];
    final model = _EchoModel(seen);
    final chat = model.startChat(history: [Content.text('alt')]);
    await chat.sendMessage(Content.text('eins'));
    await chat.sendMessage(Content.text('zwei'));
    expect(seen, [2, 4]); // Verlauf + neue Nachricht
  });
}

class _EchoModel extends AiModel {
  _EchoModel(this.seen);
  final List<int> seen;

  @override
  Future<AiResponse> generateContent(Iterable<Content> contents) async {
    seen.add(contents.length);
    return const AiResponse('ok');
  }
}
