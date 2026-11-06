import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/data/child_device_repository.dart';
import '../../auth/domain/account.dart';
import '../../auth/domain/child_model.dart';
import '../../rewards/data/system_rewards_initializer.dart';
import '../../rewards/data/xp_service.dart';
import '../domain/school_models.dart';

// ============================================================================
// SCHULE
//
// Schule, Lehrerliste und Karten laufen über die Cloud Functions
// (functions/school.js). Klassen und Schüler legen Lehrkräfte direkt in
// Firestore an, die Rules erlauben das allen Lehrkräften der Schule.
// Schüler liegen unter users/school_<id>/children – wie Kinder einer Familie.
// ============================================================================

/// Einladungslink einer Schule von Lerndex: …/schule/CODE
String? schoolSignupFromPath(String path) =>
    RegExp(r'^/schule/([A-Za-z0-9-]{8,9})/?$').firstMatch(path)?.group(1);

/// QR-Karte einer Lehrkraft: …/l/TOKEN
String? teacherCardFromPath(String path) =>
    RegExp(r'^/l/([A-Za-z0-9]{16,64})/?$').firstMatch(path)?.group(1);

class SchoolRepository {
  SchoolRepository(this._functions, this._firestore, this._auth);

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<Map<String, dynamic>> _call(String name, [Object? data]) async {
    final result = await _functions.httpsCallable(name).call(data ?? {});
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Schul-Rolle aus dem Token (nach Beitritt erst mit frischem Token).
  Future<SchoolMembership?> membership({bool refresh = false}) async {
    final user = _auth.currentUser;
    if (user == null || user.isChildDevice) return null;
    final claims = (await user.getIdTokenResult(refresh)).claims ?? const {};
    final schoolId = claims['schoolId'] as String?;
    final role = claims['schoolRole'] as String?;
    if (schoolId == null || role == null) return null;
    return SchoolMembership(schoolId: schoolId, role: role);
  }

  // ── Schule, Lehrkräfte ────────────────────────────────────────────────────

  /// Schule mit dem Einladungscode von Lerndex anlegen (…/schule/CODE).
  /// Gibt den Namen der Schule zurück.
  Future<String> createSchool({required String code, String? name}) async {
    final data = await _call('createSchool', {
      'code': code,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    });
    await _auth.currentUser?.getIdToken(true);
    return data['schoolName'] as String? ?? '';
  }

  /// Schulleitung: Lehrkraft anlegen. Gibt die Karte zum Ausdrucken zurück.
  Future<TeacherCard> createTeacher(String name, String schoolName) async {
    final data = await _call('createTeacher', {'name': name});
    return TeacherCard(
      name: name.trim(),
      schoolName: schoolName,
      link: Uri.parse('${webAppOrigin()}/l/${data['token']}'),
    );
  }

  /// Schulleitung: neue Karte (alte wird ungültig). [resetPin]: PIN vergessen.
  Future<TeacherCard> reissueTeacherCard(
    SchoolMember teacher,
    String schoolName, {
    bool resetPin = false,
  }) async {
    final data = await _call('reissueTeacherCard', {
      'teacherId': teacher.uid,
      'resetPin': resetPin,
    });
    return TeacherCard(
      name: teacher.name,
      schoolName: schoolName,
      link: Uri.parse('${webAppOrigin()}/l/${data['token']}'),
    );
  }

  /// Lehrergerät: Karte prüfen. Gibt zurück, ob schon eine PIN festgelegt
  /// ist, und den Namen der Lehrkraft.
  Future<({bool pinSet, String name})> teacherCardInfo(String token) async {
    final data = await _call('redeemTeacherCard', {'token': token});
    return (
      pinSet: data['pinSet'] == true,
      name: data['name'] as String? ?? '',
    );
  }

  /// Lehrergerät: mit Karte und PIN anmelden ([firstPin]: PIN festlegen).
  /// Gibt false bei falscher PIN zurück.
  Future<bool> signInWithTeacherCard(
    String token,
    String pin, {
    bool firstPin = false,
  }) async {
    final data = await _call('redeemTeacherCard', {
      'token': token,
      if (firstPin) 'newPin': pin else 'pin': pin,
    });
    final custom = data['token'] as String?;
    if (custom == null) return false;
    // Im Browser (Klassen-PC): Anmeldung nur in diesem Tab speichern, nicht
    // dauerhaft – sonst sieht die nächste Person am PC alle Klassen.
    if (kIsWeb) {
      try {
        await _auth.setPersistence(Persistence.SESSION);
      } catch (e) {
        debugPrint('⚠️ Anmeldung nur für den Tab nicht möglich: $e');
      }
    }
    await _auth.signInWithCustomToken(custom);
    return true;
  }

  Future<void> removeTeacher(String uid) =>
      _call('removeTeacher', {'uid': uid});

  /// Lizenz der Schule (null = keine). Liest das Schulkonto `users/school_<id>`.
  Stream<DateTime?> watchLicense(String schoolId) => _firestore
      .collection('users')
      .doc(schoolOwnerUid(schoolId))
      .snapshots()
      .map((s) => (s.data()?['schoolLicenseUntil'] as Timestamp?)?.toDate());

  Stream<String> watchSchoolName(String schoolId) => _firestore
      .collection('schools')
      .doc(schoolId)
      .snapshots()
      .map((s) => s.data()?['name'] as String? ?? '');

  Stream<List<SchoolMember>> watchMembers(String schoolId) => _firestore
      .collection('schools')
      .doc(schoolId)
      .collection('members')
      .snapshots()
      .map(
        (s) => s.docs.map(SchoolMember.fromDoc).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ),
      );

  // ── Klassen ───────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _classes(String schoolId) =>
      _firestore.collection('schools').doc(schoolId).collection('classes');

  Stream<List<SchoolClass>> watchClasses(String schoolId) =>
      _classes(schoolId).snapshots().map(
        (s) =>
            s.docs.map(SchoolClass.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  Future<void> addClass(
    String schoolId, {
    required String name,
    required int grade,
    required String schoolType,
  }) => _classes(schoolId).add({
    'name': name,
    'grade': grade,
    'schoolType': schoolType,
    'createdAt': FieldValue.serverTimestamp(),
  });

  /// Nur leere Klassen (Schüler vorher löschen oder verschieben).
  Future<void> deleteClass(String schoolId, String classId) =>
      _classes(schoolId).doc(classId).delete();

  // ── Schüler ───────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _students(String schoolId) =>
      _firestore
          .collection('users')
          .doc(schoolOwnerUid(schoolId))
          .collection('children');

  Stream<List<ChildModel>> watchStudents(String schoolId, String classId) =>
      _students(schoolId)
          .where('classId', isEqualTo: classId)
          .snapshots()
          .map(
            (s) =>
                s.docs.map((d) => ChildModel.fromMap(d.data(), d.id)).toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  ),
          );

  /// Schüler einer Klasse anlegen. Bewusst ohne KI-Vorladen: bei einer
  /// ganzen Klasse wären das sofort hunderte KI-Aufrufe. Das Schülergerät
  /// lädt beim ersten Start nur die eigenen Fächer.
  Future<void> addStudents(
    String schoolId,
    SchoolClass schoolClass,
    List<String> names,
  ) async {
    final owner = schoolOwnerUid(schoolId);
    final rewards = SystemRewardsInitializer(_firestore);
    for (final name in names) {
      final ref = await _students(schoolId).add({
        'name': name,
        'classId': schoolClass.id,
        'grade': schoolClass.grade,
        'schoolType': schoolClass.schoolType,
        'age': (schoolClass.grade + 5).clamp(6, 16),
        'xp': 0,
        'level': 1,
        'streak': 0,
        'totalLearningSeconds': 0,
        'xpToNextLevel': XPService.calculateXPForLevel(1),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await rewards.initializeSystemRewards(userId: owner, childId: ref.id);
    }
  }

  Future<void> renameStudent(String schoolId, String studentId, String name) =>
      _students(schoolId).doc(studentId).update({'name': name});

  /// Komplett löschen inkl. Lexi-Chats, Karten und Gerätekonto (Function –
  /// Lehrkräfte dürfen die Chats selbst nicht lesen).
  Future<void> deleteStudent(String studentId) =>
      _call('deleteStudent', {'studentId': studentId});

  /// Neue QR-Karten für die Schüler. Alte Karten werden ungültig.
  Future<List<StudentCard>> createCards(
    List<ChildModel> students,
    String className,
  ) async {
    final cards = <StudentCard>[];
    // Die Function nimmt höchstens 60 Schüler pro Aufruf
    for (var i = 0; i < students.length; i += 60) {
      final chunk = students.skip(i).take(60).toList();
      final data = await _call('createStudentCards', {
        'studentIds': chunk.map((s) => s.id).toList(),
      });
      final byId = {for (final s in chunk) s.id: s.name};
      for (final card in (data['cards'] as List).cast<Map>()) {
        cards.add(
          StudentCard(
            studentId: card['studentId'] as String,
            name: byId[card['studentId']] ?? '',
            className: className,
            link: Uri.parse('${webAppOrigin()}/s/${card['token']}'),
          ),
        );
      }
    }
    return cards;
  }
}

final schoolRepositoryProvider = Provider<SchoolRepository>((ref) {
  return SchoolRepository(
    lerndexFunctions(),
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});

/// Schul-Rolle des angemeldeten Kontos, null ohne Schule.
/// Nach Gründen/Beitreten mit ref.invalidate neu laden.
final schoolMembershipProvider = FutureProvider<SchoolMembership?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(schoolRepositoryProvider).membership();
});

final schoolLicenseProvider = StreamProvider.autoDispose
    .family<DateTime?, String>((ref, id) {
      return ref.watch(schoolRepositoryProvider).watchLicense(id);
    });

final schoolNameProvider = StreamProvider.autoDispose.family<String, String>((
  ref,
  id,
) {
  return ref.watch(schoolRepositoryProvider).watchSchoolName(id);
});

final schoolClassesProvider = StreamProvider.autoDispose
    .family<List<SchoolClass>, String>((ref, schoolId) {
      return ref.watch(schoolRepositoryProvider).watchClasses(schoolId);
    });

final schoolMembersProvider = StreamProvider.autoDispose
    .family<List<SchoolMember>, String>((ref, schoolId) {
      return ref.watch(schoolRepositoryProvider).watchMembers(schoolId);
    });

final classStudentsProvider = StreamProvider.autoDispose
    .family<List<ChildModel>, ({String schoolId, String classId})>((ref, ids) {
      return ref
          .watch(schoolRepositoryProvider)
          .watchStudents(ids.schoolId, ids.classId);
    });
