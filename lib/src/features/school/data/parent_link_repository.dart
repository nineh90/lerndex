import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/data/child_device_repository.dart';
import '../../auth/domain/account.dart';
import '../../auth/domain/child_model.dart';

// ============================================================================
// ELTERN ↔ SCHULKIND
//
// Die Lehrkraft druckt pro Kind einen Elternbrief (createParentLetters) mit
// einem Eltern-Code (…/e/CODE) und einer Heimkarte (…/s/TOKEN, zum Lernen zu
// Hause). Eltern verbinden ihr Konto mit dem Code (linkSchoolChild). Das Kind
// bleibt bei der Schule; Eltern sehen Statistik und Lexi-Gespräche und
// pflegen Belohnungen. Dafür braucht es kein Abo.
// ============================================================================

/// Eltern-Code aus einem Link wie /e/K7MXQ2PA.
String? parentLinkCodeFromPath(String path) =>
    RegExp(r'^/e/([A-Za-z0-9-]{8,9})/?$').firstMatch(path)?.group(1);

/// Verbindung eines Elternkontos mit einem Schulkind
/// (users/{uid}/linkedChildren/{schoolId}_{studentId}).
class SchoolChildLink {
  const SchoolChildLink({
    required this.schoolId,
    required this.studentId,
    required this.ownerUid,
    required this.name,
    required this.schoolName,
    required this.className,
  });

  final String schoolId;
  final String studentId;

  /// `school_<schoolId>` – dort liegt das Kind
  final String ownerUid;
  final String name;
  final String schoolName;
  final String className;

  factory SchoolChildLink.fromMap(Map<String, dynamic> d) => SchoolChildLink(
    schoolId: d['schoolId'] as String? ?? '',
    studentId: d['studentId'] as String? ?? '',
    ownerUid: d['ownerUid'] as String? ?? '',
    name: d['name'] as String? ?? '',
    schoolName: d['schoolName'] as String? ?? '',
    className: d['className'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is SchoolChildLink &&
      other.schoolId == schoolId &&
      other.studentId == studentId;

  @override
  int get hashCode => Object.hash(schoolId, studentId);
}

/// Elternbrief eines Kindes (Codes gibt es nur direkt nach dem Erzeugen).
class ParentLetter {
  const ParentLetter({
    required this.studentName,
    required this.className,
    required this.schoolName,
    required this.parentCode,
    required this.homeLink,
  });

  final String studentName;
  final String className;
  final String schoolName;
  final String parentCode;
  final Uri homeLink;

  Uri get parentLink => Uri.parse('${webAppOrigin()}/e/$parentCode');

  /// Zum Abtippen: K7MX-Q2PA
  String get displayCode =>
      '${parentCode.substring(0, 4)}-${parentCode.substring(4)}';
}

class ParentLinkRepository {
  ParentLinkRepository(this._functions, this._firestore, this._auth);

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const _pendingKey = 'pending_parent_link';

  Future<Map<String, dynamic>> _call(String name, Object data) async {
    final result = await _functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Lehrkraft: Elternbriefe für Schüler (alte Codes werden ungültig).
  Future<List<ParentLetter>> createLetters(
    List<ChildModel> students, {
    required String className,
    required String schoolName,
  }) async {
    final data = await _call('createParentLetters', {
      'studentIds': students.map((s) => s.id).toList(),
    });
    final names = {for (final s in students) s.id: s.name};
    return [
      for (final l in (data['letters'] as List).cast<Map>())
        ParentLetter(
          studentName: names[l['studentId']] ?? '',
          className: className,
          schoolName: schoolName,
          parentCode: l['parentCode'] as String,
          homeLink: Uri.parse('${webAppOrigin()}/s/${l['homeToken']}'),
        ),
    ];
  }

  /// Eltern: mit dem Code aus dem Elternbrief verbinden. Gibt den Namen des
  /// Kindes zurück.
  Future<String> link(String code) async {
    final data = await _call('linkSchoolChild', {'code': code});
    return data['name'] as String? ?? '';
  }

  Future<void> unlink(SchoolChildLink link) => _call('unlinkSchoolChild', {
    'schoolId': link.schoolId,
    'studentId': link.studentId,
  });

  /// Code aus einem gescannten Link merken, bis ein Elternteil angemeldet ist.
  Future<void> rememberPending(String code) async =>
      (await SharedPreferences.getInstance()).setString(_pendingKey, code);

  /// Gemerkten Code einlösen (nach der Anmeldung). Gibt den Namen des Kindes
  /// zurück oder null, wenn nichts offen war. Wirft bei ungültigem Code
  /// (der Code ist dann vergessen).
  Future<String?> redeemPending() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingKey);
    if (code == null) return null;
    await prefs.remove(_pendingKey);
    return link(code);
  }

  Stream<List<SchoolChildLink>> watchLinks() {
    final user = _auth.currentUser;
    if (user == null || user.isChildDevice || user.isTeacherDevice) {
      return Stream.value(const []);
    }
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('linkedChildren')
        .snapshots()
        .map(
          (s) => s.docs.map((d) => SchoolChildLink.fromMap(d.data())).toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
        );
  }

  Stream<ChildModel?> watchChild(SchoolChildLink link) => _firestore
      .collection('users')
      .doc(link.ownerUid)
      .collection('children')
      .doc(link.studentId)
      .snapshots()
      .map((d) => d.exists ? ChildModel.fromMap(d.data()!, d.id) : null)
      .handleError((_) {});
}

final parentLinkRepositoryProvider = Provider<ParentLinkRepository>((ref) {
  return ParentLinkRepository(
    lerndexFunctions(),
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});

/// Mit dem eigenen Konto verbundene Schulkinder.
final schoolChildLinksProvider = StreamProvider<List<SchoolChildLink>>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(parentLinkRepositoryProvider).watchLinks();
});

/// Profil eines verbundenen Schulkindes (live).
final linkedSchoolChildProvider =
    StreamProvider.family<ChildModel?, SchoolChildLink>((ref, link) {
      return ref.watch(parentLinkRepositoryProvider).watchChild(link);
    });
