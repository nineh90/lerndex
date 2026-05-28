import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  // Wird beim ersten Aufruf befüllt und danach wiederverwendet – PackageInfo
  // muss nur einmal pro App-Session vom nativen Bundle gelesen werden.
  PackageInfo? _packageInfo;

  Future<String> _appVersion() async {
    final info = _packageInfo ??= await PackageInfo.fromPlatform();
    final build = info.buildNumber;
    return build.isEmpty ? info.version : '${info.version}+$build';
  }

  Future<void> sendFeedback({
    required String subject,
    required String message,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Nicht eingeloggt – Feedback nicht möglich.');
    }
    final userEmail = user.email ?? '';

    final trimmedSubject = subject.trim();
    final trimmedMessage = message.trim();

    final effectiveSubject = trimmedSubject.isEmpty
        ? 'Feedback aus der Lerndex-App'
        : 'Lerndex-Feedback: $trimmedSubject';

    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final appVersion = await _appVersion();

    final mailBody = StringBuffer()
      ..writeln(trimmedMessage)
      ..writeln()
      ..writeln('— — — — — — — — — — — — — — —')
      ..writeln('Absender: $userEmail')
      ..writeln('User-ID: ${user.uid}')
      ..writeln('App-Version: $appVersion')
      ..writeln('Plattform: $platform');

    final data = <String, dynamic>{
      // Trigger-Email-Extension-Felder
      'to': [_supportAddress],
      'message': {
        'subject': effectiveSubject,
        'text': mailBody.toString(),
      },
      // Meta-Felder (nur User-E-Mail, keine Kind-Daten – DSGVO)
      'userId': user.uid,
      'userEmail': userEmail,
      'subject': trimmedSubject,
      'messageBody': trimmedMessage,
      'appVersion': appVersion,
      'platform': platform,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (userEmail.isNotEmpty) {
      data['replyTo'] = userEmail;
    }

    await _firestore.collection('mail').add(data);
  }
}

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository(FirebaseFirestore.instance);
});
