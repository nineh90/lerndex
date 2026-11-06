import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/ai/ai_model.dart';
import 'package:lerndex/src/ai/ai_response_parser.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/tutor/domain/chat_message.dart';

ChatMessage _msg(String text, {bool user = false, bool exclude = false}) =>
    ChatMessage(
      id: text,
      text: text,
      isUser: user,
      timestamp: DateTime(2026),
      excludeFromAi: exclude,
    );

String _textOf(Content c) => (c.parts.single as TextPart).text;

void main() {
  group('AiResponseParser.normalizeChoices', () {
    test('Zahlen als JSON-Werte werden zu Text', () {
      final r = AiResponseParser.normalizeChoices([12, 15, 18, 21], 15);
      expect(r, isNotNull);
      expect(r!.options, ['12', '15', '18', '21']);
      expect(r.answer, '15');
    });

    test('doppelte Optionen → verworfen (auch Groß/klein, Leerzeichen)', () {
      expect(
        AiResponseParser.normalizeChoices(['a', 'b', 'c', 'a'], 'a'),
        isNull,
      );
      expect(
        AiResponseParser.normalizeChoices([
          'Hund',
          'hund ',
          'Katze',
          'Maus',
        ], 'Hund'),
        isNull,
      );
    });

    test('Antwort nicht unter den Optionen → verworfen', () {
      expect(
        AiResponseParser.normalizeChoices(['1', '2', '3', '4'], '5'),
        isNull,
      );
    });

    test('Antwort mit anderer Schreibweise zählt als Option', () {
      final r = AiResponseParser.normalizeChoices([
        'Berlin',
        'Hamburg',
        'München',
        'Köln',
      ], ' berlin');
      expect(r!.answer, 'Berlin');
    });

    test('falsche Anzahl oder leere Option → verworfen', () {
      expect(AiResponseParser.normalizeChoices(['1', '2', '3'], '1'), isNull);
      expect(
        AiResponseParser.normalizeChoices(['1', '', '3', '4'], '1'),
        isNull,
      );
      expect(AiResponseParser.normalizeChoices('1,2,3,4', '1'), isNull);
    });
  });

  group('VertexAIService.parseQuizResponse', () {
    test('Zahlen-Antworten werden nicht mehr still verworfen', () {
      final json = jsonEncode([
        {
          'question': 'Was ist 3 · 5?',
          'options': [8, 15, 12, 35],
          'answer': 15,
          'difficulty': 'easy',
          'topic': 'Einmaleins',
        },
      ]);
      final q = VertexAIService.parseQuizResponse(json, 3, subject: 'mathe');
      expect(q, hasLength(1));
      expect(q.single.answer, '15');
      expect(q.single.options, contains('15'));
    });

    test('Frage mit doppelten Optionen fällt raus, die andere bleibt', () {
      final json = jsonEncode([
        {
          'question': 'Was ist 2 + 2?',
          'options': ['4', '4', '5', '6'],
          'answer': '4',
        },
        {
          'question': 'Was ist 2 + 3?',
          'options': ['4', '5', '6', '7'],
          'answer': '5',
        },
      ]);
      final q = VertexAIService.parseQuizResponse(json, 2, subject: 'mathe');
      expect(q.map((e) => e.question), ['Was ist 2 + 3?']);
    });

    test('kein Objekt im Array → übersprungen, kein Absturz', () {
      final q = VertexAIService.parseQuizResponse('["x", 3]', 3);
      expect(q, isEmpty);
    });
  });

  group('VertexAIService.parseGeneratedQuestions', () {
    test('Zahlen und Lösung werden übernommen', () {
      final json = jsonEncode([
        {
          'question': 'Wie viel ist 7 + 8?',
          'options': [14, 15, 16, 17],
          'correctAnswer': 15,
          'solution': '7 + 3 = 10, dann noch 5.',
          'difficulty': 'easy',
          'topic': 'Addition',
        },
      ]);
      final q = VertexAIService.parseGeneratedQuestions(json);
      expect(q, hasLength(1));
      expect(q.single.correctAnswer, '15');
      expect(q.single.solution, isNotEmpty);
    });

    test('doppelte Optionen → Aufgabe verworfen', () {
      final json = jsonEncode([
        {
          'question': 'Welche Zahl ist gerade?',
          'options': ['2', '2', '3', '5'],
          'correctAnswer': '2',
        },
      ]);
      expect(VertexAIService.parseGeneratedQuestions(json), isEmpty);
    });
  });

  group('VertexAIService.buildTutorHistory', () {
    test('Antworten der App samt Frage gehen nicht an die KI', () {
      final history = VertexAIService.buildTutorHistory([
        _msg('Hallo Mia!', exclude: true), // Begrüßung
        _msg('Was ist ein Bruch?', user: true),
        _msg('Ein Bruch ist ein Teil eines Ganzen.'),
        _msg('verbotene Frage', user: true, exclude: true),
        _msg('Dabei helfe ich nicht.', exclude: true),
        _msg('Und 1/2?', user: true),
      ]);
      expect(history.map(_textOf), [
        'Was ist ein Bruch?',
        'Ein Bruch ist ein Teil eines Ganzen.',
        'Und 1/2?',
      ]);
      expect(history.map((c) => c.role), ['user', 'model', 'user']);
    });

    test('überlange Frage fällt samt Antwort heraus', () {
      final history = VertexAIService.buildTutorHistory([
        _msg('x' * 501, user: true),
        _msg('Deine Frage ist zu lang.'),
        _msg('Kurz: 2 + 2?', user: true),
      ]);
      expect(history.map(_textOf), ['Kurz: 2 + 2?']);
    });

    test('höchstens die letzten 10 Nachrichten', () {
      final history = VertexAIService.buildTutorHistory([
        for (var i = 0; i < 12; i++) ...[
          _msg('Frage $i', user: true),
          _msg('Antwort $i'),
        ],
      ]);
      expect(history, hasLength(10));
      expect(_textOf(history.last), 'Antwort 11');
    });

    test('Ladeanzeige wird übersprungen', () {
      final history = VertexAIService.buildTutorHistory([
        _msg('Frage', user: true),
        ChatMessage.loading(),
      ]);
      expect(history, hasLength(1));
    });
  });

  group('Name und Modell-Cache', () {
    test('nur der Vorname', () {
      expect(VertexAIService.firstNameOf('Mia Sophie Müller'), 'Mia');
      expect(VertexAIService.firstNameOf('  Ben  '), 'Ben');
      expect(VertexAIService.firstNameOf(''), 'du');
    });

    test('Profiländerung ergibt neuen Modell-Schlüssel', () {
      const child = ChildModel(
        id: 'c1',
        name: 'Mia',
        grade: 3,
        schoolType: 'Grundschule',
        age: 8,
      );
      final key = VertexAIService.tutorModelKey(child);
      expect(
        VertexAIService.tutorModelKey(child.copyWith(name: 'Lea')),
        isNot(key),
      );
      expect(VertexAIService.tutorModelKey(child.copyWith(age: 9)), isNot(key));
      expect(
        VertexAIService.tutorModelKey(child.copyWith(grade: 4)),
        isNot(key),
      );
      expect(VertexAIService.tutorModelKey(child), key);
    });
  });

  group('Fehlertexte', () {
    test('Tageslimit der Function zeigt deren Text', () {
      const e = AiServerException(
        'resource-exhausted',
        'Für heute ist Lexis Denkpause erreicht. Morgen geht es weiter.',
      );
      expect(VertexAIService.errorTextFor(e), contains('Denkpause'));
      expect(VertexAIService.errorTextFor(e), isNot(contains('nochmal')));
    });

    test('Timeout und sonstige Fehler', () {
      expect(
        VertexAIService.errorTextFor(TimeoutException('x')),
        contains('zu lange'),
      );
      expect(VertexAIService.errorTextFor(Exception('x')), contains('Ups'));
      expect(
        VertexAIService.taskErrorTextFor(Exception('x')),
        isNot(contains('Exception')),
      );
    });
  });
}
