import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/services/tutor_chat_cleanup_service.dart';

void main() {
  const uid = 'school_s1';
  const childId = 'k1';

  Future<FakeFirebaseFirestore> setup({required String status}) async {
    final fs = FakeFirebaseFirestore();
    final child = fs.doc('users/$uid/children/$childId');
    final session = child.collection('tutor_sessions').doc('s1');
    await session.set({'status': status, 'messageCount': 2});
    await session.collection('messages').add({'text': 'Hallo'});
    await session.collection('messages').add({'text': 'Hi'});
    await child.collection('active_tutor_chat').add({'text': 'x'});
    return fs;
  }

  test('löscht Nachrichten und Session, ohne sie vorher zu ändern', () async {
    final fs = await setup(status: 'completed');
    await TutorChatCleanupService(
      firestore: fs,
    ).deleteSession(userId: uid, childId: childId, sessionId: 's1');

    final base = 'users/$uid/children/$childId';
    expect((await fs.doc('$base/tutor_sessions/s1').get()).exists, isFalse);
    expect(
      (await fs.collection('$base/tutor_sessions/s1/messages').get()).docs,
      isEmpty,
    );
    // Altes Gespräch gelöscht → aktiver Chat bleibt
    expect(
      (await fs.collection('$base/active_tutor_chat').get()).docs,
      hasLength(1),
    );
  });

  test('aktive Session: active_tutor_chat wird mit geleert', () async {
    final fs = await setup(status: 'active');
    await TutorChatCleanupService(
      firestore: fs,
    ).deleteSession(userId: uid, childId: childId, sessionId: 's1');
    expect(
      (await fs
              .collection('users/$uid/children/$childId/active_tutor_chat')
              .get())
          .docs,
      isEmpty,
    );
  });
}
