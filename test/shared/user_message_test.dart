import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/shared/user_message.dart';

class _Friendly implements FriendlyException {
  @override
  String get message => 'Schon verständlich.';
}

void main() {
  group('userMessage', () {
    test('Meldungen der Functions (deutsch) gehen durch', () {
      final e = FirebaseFunctionsException(
        code: 'not-found',
        message: 'Diese Karte gilt nicht mehr.',
      );
      expect(userMessage(e), 'Diese Karte gilt nicht mehr.');
    });

    test('Absturz der Function zeigt kein INTERNAL', () {
      final e = FirebaseFunctionsException(
        code: 'internal',
        message: 'INTERNAL',
      );
      expect(userMessage(e), isNot(contains('INTERNAL')));
      expect(userMessage(e), contains('nicht geklappt'));
    });

    test('Netzwerkfehler der Functions → Verbindungshinweis', () {
      final e = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Service unavailable',
      );
      expect(userMessage(e), contains('Verbindung'));
    });

    test('Firestore-Fehler ohne technischen Code im Text', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
      final text = userMessage(e);
      expect(text, contains('Berechtigung'));
      expect(text, isNot(contains('cloud_firestore')));
    });

    test('Auth-Fehler', () {
      expect(
        userMessage(FirebaseAuthException(code: 'network-request-failed')),
        contains('Verbindung'),
      );
      expect(
        userMessage(FirebaseAuthException(code: 'popup-closed-by-user')),
        'Anmeldung abgebrochen.',
      );
    });

    test('Texte und lesbare Fehler bleiben', () {
      expect(userMessage('Falsches Passwort.'), 'Falsches Passwort.');
      expect(userMessage(_Friendly()), 'Schon verständlich.');
    });

    test('Sonstiges → allgemeiner Satz statt toString()', () {
      expect(userMessage(StateError('kaputt')), isNot(contains('kaputt')));
      expect(userMessage(PlatformException(code: 'xyz')), contains('nicht'));
      expect(userMessage(TimeoutException('x')), contains('Verbindung'));
    });
  });
}
