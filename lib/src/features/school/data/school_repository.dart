import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  Future<void> createSchool(String name) async {
    await _call('createSchool', {'name': name});
    await _auth.currentUser?.getIdToken(true);
  }

  Future<({String code, DateTime expiresAt})> createTeacherInvite() async {
    final data = await _call('createTeacherInvite');
    return (
      code: data['code'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String),
    );
  }

  /// Gibt den Namen der Schule zurück.
  Future<String> joinSchool(String code) async {
    final data = await _call('joinSchool', {'code': code});
    await _auth.currentUser?.getIdToken(true);
    return data['schoolName'] as String? ?? '';
  }

  Future<void> removeTeacher(String uid) => _call('removeTeacher', {'uid': uid});

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
      .map((s) => s.docs.map(SchoolMember.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  // ── Klassen ───────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _classes(String schoolId) =>
      _firestore.collection('schools').doc(schoolId).collection('classes');

  Stream<List<SchoolClass>> watchClasses(String schoolId) =>
      _classes(schoolId).snapshots().map(
        (s) => s.docs.map(SchoolClass.fromDoc).toList()
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
            (s) => s.docs.map((d) => ChildModel.fromMap(d.data(), d.id)).toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
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

final schoolNameProvider = StreamProvider.family<String, String>((ref, id) {
  return ref.watch(schoolRepositoryProvider).watchSchoolName(id);
});

final schoolClassesProvider =
    StreamProvider.family<List<SchoolClass>, String>((ref, schoolId) {
      return ref.watch(schoolRepositoryProvider).watchClasses(schoolId);
    });

final schoolMembersProvider =
    StreamProvider.family<List<SchoolMember>, String>((ref, schoolId) {
      return ref.watch(schoolRepositoryProvider).watchMembers(schoolId);
    });

final classStudentsProvider =
    StreamProvider.family<
      List<ChildModel>,
      ({String schoolId, String classId})
    >((ref, ids) {
      return ref
          .watch(schoolRepositoryProvider)
          .watchStudents(ids.schoolId, ids.classId);
    });
