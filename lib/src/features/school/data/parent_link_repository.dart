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

/// Eltern-Code aus einem gescannten Elternbrief, gemerkt bis zur Anmeldung.
/// Gilt einen Tag; danach (und beim Abmelden) ist er vergessen, damit er
/// nicht Tage später einem ganz anderen Konto zugeordnet wird.
abstract final class PendingParentCode {
  static const _key = 'pending_parent_link';
  static const maxAge = Duration(days: 1);

  static Future<void> remember(String code, {DateTime? now}) async {
    final savedAt = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await (await SharedPreferences.getInstance()).setString(
      _key,
      '$savedAt|$code',
    );
  }

  /// Code, wenn er nicht älter als [maxAge] ist. Abgelaufene (und alte
  /// Einträge ohne Zeitstempel) werden gelöscht.
  static Future<String?> read({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null) return null;
    final parts = value.split('|');
    final savedAt = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final age = savedAt == null
        ? null
        : (now ?? DateTime.now()).difference(
            DateTime.fromMillisecondsSinceEpoch(savedAt),
          );
    if (age == null || age.isNegative || age > maxAge || parts[1].isEmpty) {
      await prefs.remove(_key);
      return null;
    }
    return parts[1];
  }

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

class ParentLinkRepository {
  ParentLinkRepository(this._functions, this._firestore, this._auth);

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<Map<String, dynamic>> _call(String name, Object data) async {
    final result = await _functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Lehrkraft: Elternbriefe für Schüler. Alte Eltern-Codes und Heimkarten
  /// der Kinder werden ungültig – die neuen Briefe müssen also wirklich bei
  /// den Eltern ankommen.
  Future<List<ParentLetter>> createLetters(
    List<ChildModel> students, {
    required String className,
    required String schoolName,
  }) async {
    final letters = <ParentLetter>[];
    // Die Function nimmt höchstens 60 Schüler pro Aufruf (wie bei den Karten)
    for (var i = 0; i < students.length; i += 60) {
      final chunk = students.skip(i).take(60).toList();
      final data = await _call('createParentLetters', {
        'studentIds': chunk.map((s) => s.id).toList(),
      });
      final names = {for (final s in chunk) s.id: s.name};
      for (final l in (data['letters'] as List).cast<Map>()) {
        letters.add(
          ParentLetter(
            studentName: names[l['studentId']] ?? '',
            className: className,
            schoolName: schoolName,
            parentCode: l['parentCode'] as String,
            homeLink: Uri.parse('${webAppOrigin()}/s/${l['homeToken']}'),
          ),
        );
      }
    }
    return letters;
  }

  /// Eltern: zu welchem Kind gehört der Code? (Vorname, Klasse, Schule –
  /// verbindet noch nicht)
  Future<({String firstName, String className, String schoolName})> preview(
    String code,
  ) async {
    final data = await _call('previewSchoolChild', {'code': code});
    return (
      firstName: data['firstName'] as String? ?? '',
      className: data['className'] as String? ?? '',
      schoolName: data['schoolName'] as String? ?? '',
    );
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
  Future<void> rememberPending(String code) => PendingParentCode.remember(code);

  /// Gemerkter Code (höchstens einen Tag alt) oder null.
  Future<String?> pendingCode() => PendingParentCode.read();

  /// Gemerkten Code vergessen (eingelöst, abgelehnt oder abgemeldet).
  Future<void> clearPending() => PendingParentCode.clear();

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
          (s) =>
              s.docs.map((d) => SchoolChildLink.fromMap(d.data())).toList()
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
final schoolChildLinksProvider =
    StreamProvider.autoDispose<List<SchoolChildLink>>((ref) {
      ref.watch(authStateChangesProvider);
      return ref.watch(parentLinkRepositoryProvider).watchLinks();
    });

/// Profil eines verbundenen Schulkindes (live).
final linkedSchoolChildProvider = StreamProvider.autoDispose
    .family<ChildModel?, SchoolChildLink>((ref, link) {
      return ref.watch(parentLinkRepositoryProvider).watchChild(link);
    });
