import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Schreibt Feedback-Nachrichten in die `mail/` Collection.
///
/// Das Format folgt der Firebase Trigger-Email-Extension (Felder `to` und
/// `message.subject` / `message.text`). Die Extension verschickt das Dokument
/// automatisch per E-Mail an den Empfänger.
class FeedbackRepository {
  FeedbackRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const String _supportAddress = 'support@lerndex.de';

  Future<void> sendFeedback({
    required String subject,
    required String message,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Nicht eingeloggt – Feedback nicht möglich.');
    }

    final trimmedSubject = subject.trim();
    final trimmedMessage = message.trim();

    final info = await PackageInfo.fromPlatform();
    final appVersion = '${info.version}+${info.buildNumber}';

    final data = <String, dynamic>{
      'to': [_supportAddress],
      'message': {
        'subject': trimmedSubject.isEmpty
            ? 'Feedback aus der Lerndex App'
            : 'Feedback: $trimmedSubject',
        'text': trimmedMessage,
      },
      'userId': user.uid,
      'userEmail': user.email,
      'appVersion': appVersion,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Antworten des Supports gehen so direkt an den Nutzer, nicht an support@.
    final email = user.email;
    if (email != null && email.isNotEmpty) {
      data['replyTo'] = email;
    }

    await _firestore.collection('mail').add(data);
  }
}

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository(FirebaseFirestore.instance);
});
