import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Schreibt Feedback-Nachrichten in die `mail/` Collection.
///
/// Das Format folgt der Firebase Trigger-Email-Extension (Felder `to` und
/// `message.subject` / `message.text`). Die Extension verschickt das Dokument
/// automatisch per E-Mail an den Empfänger. Optionale Screenshots werden nach
/// Firebase Storage hochgeladen und als `message.attachments` (Download-URL)
/// verlinkt – nodemailer lädt die URL und hängt sie an die Mail.
class FeedbackRepository {
  FeedbackRepository(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  static const String _supportAddress = 'support@lerndex.de';

  Future<void> sendFeedback({
    required String subject,
    required String message,
    File? screenshot,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Nicht eingeloggt – Feedback nicht möglich.');
    }

    final trimmedSubject = subject.trim();
    final trimmedMessage = message.trim();

    final info = await PackageInfo.fromPlatform();
    final appVersion = '${info.version}+${info.buildNumber}';

    final messageData = <String, dynamic>{
      'subject': trimmedSubject.isEmpty
          ? 'Feedback aus der Lerndex App'
          : 'Feedback: $trimmedSubject',
      'text': trimmedMessage,
    };

    // Screenshot optional hochladen und als Attachment verlinken.
    if (screenshot != null) {
      final attachment = await _uploadScreenshot(screenshot, user.uid);
      messageData['attachments'] = [attachment];
    }

    final data = <String, dynamic>{
      'to': [_supportAddress],
      'message': messageData,
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

  /// Lädt den Screenshot nach `feedback/{uid}/...` und gibt das nodemailer-
  /// Attachment ({filename, path}) mit Download-URL zurück.
  Future<Map<String, String>> _uploadScreenshot(File file, String uid) async {
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt = (ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp')
        ? ext
        : 'jpg';
    final contentType = switch (safeExt) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('feedback/$uid/$stamp.$safeExt');
    await ref.putFile(file, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();

    return {'filename': 'screenshot.$safeExt', 'path': url};
  }
}

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepository(FirebaseFirestore.instance, FirebaseStorage.instance);
});
