import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

// ============================================================================
// FEHLERTEXTE FÜR DIE OBERFLÄCHE
//
// Technische Fehler (Firebase, Plattform) sollen nicht roh auf dem Bildschirm
// landen („[cloud_firestore/permission-denied] …“). userMessage macht daraus
// einen kurzen deutschen Satz. Meldungen unserer Cloud Functions sind schon
// deutsch und gehen unverändert durch.
// ============================================================================

/// Fehler, deren Text schon für Menschen geschrieben ist.
abstract interface class FriendlyException implements Exception {
  String get message;
}

const _tryAgain =
    'Das hat gerade nicht geklappt. Bitte gleich noch einmal '
    'versuchen.';
const _offline =
    'Keine Verbindung zum Server. Bitte Internetverbindung prüfen '
    'und noch einmal versuchen.';
const _noPermission = 'Dafür fehlt die Berechtigung. Bitte neu anmelden.';
const _signInAgain = 'Bitte neu anmelden und noch einmal versuchen.';

/// Codes, bei denen die Meldung nicht von unseren Functions stammt, sondern
/// vom SDK (englisch) oder von einem Absturz der Function („INTERNAL“).
const _technicalFunctionCodes = {
  'internal',
  'unknown',
  'unavailable',
  'deadline-exceeded',
  'cancelled',
  'data-loss',
  'unimplemented',
};

/// Verständlicher deutscher Text für einen Fehler.
String userMessage(Object error) {
  if (error is String) return error;
  if (error is FriendlyException) return error.message;
  if (error is FirebaseFunctionsException) return _functionsMessage(error);
  if (error is FirebaseAuthException) return _authMessage(error.code);
  if (error is FirebaseException) return _firebaseMessage(error.code);
  if (error is TimeoutException) return _offline;
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('network')) return _offline;
    return _tryAgain;
  }
  return _tryAgain;
}

String _functionsMessage(FirebaseFunctionsException e) {
  switch (e.code) {
    case 'unavailable':
    case 'deadline-exceeded':
      return _offline;
    case 'unauthenticated':
      return _signInAgain;
  }
  final message = e.message?.trim() ?? '';
  if (_technicalFunctionCodes.contains(e.code) || message.isEmpty) {
    return e.code == 'permission-denied' ? _noPermission : _tryAgain;
  }
  return message;
}

String _authMessage(String code) {
  switch (code) {
    case 'network-request-failed':
      return _offline;
    case 'too-many-requests':
      return 'Zu viele Versuche. Bitte etwas warten und dann noch einmal '
          'versuchen.';
    case 'requires-recent-login':
    case 'user-token-expired':
    case 'invalid-user-token':
    case 'user-not-found':
    case 'user-disabled':
      return _signInAgain;
    case 'invalid-custom-token':
    case 'custom-token-mismatch':
      return 'Die Anmeldung ist abgelaufen. Bitte den Code noch einmal '
          'scannen.';
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
    case 'web-context-canceled':
      return 'Anmeldung abgebrochen.';
    case 'popup-blocked':
      return 'Der Browser hat das Anmeldefenster blockiert. Bitte Popups für '
          'Lerndex erlauben.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'E-Mail oder Passwort ist falsch.';
  }
  return _tryAgain;
}

String _firebaseMessage(String code) {
  switch (code) {
    case 'unavailable':
    case 'deadline-exceeded':
    case 'network-request-failed':
      return _offline;
    case 'permission-denied':
    case 'unauthorized':
      return _noPermission;
    case 'unauthenticated':
      return _signInAgain;
    case 'not-found':
    case 'object-not-found':
      return 'Das gibt es nicht mehr. Bitte die Seite neu laden.';
    case 'resource-exhausted':
    case 'quota-exceeded':
      return 'Gerade ist zu viel los. Bitte später noch einmal versuchen.';
  }
  return _tryAgain;
}
