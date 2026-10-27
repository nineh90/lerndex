import 'package:cloud_firestore/cloud_firestore.dart';

/// Schul-Rolle aus den Claims des eigenen Kontos (functions/school.js).
class SchoolMembership {
  const SchoolMembership({required this.schoolId, required this.role});

  final String schoolId;

  /// 'admin' (hat die Schule angelegt, lädt Lehrkräfte ein) oder 'teacher'
  final String role;

  bool get isAdmin => role == 'admin';
}

class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.name,
    required this.grade,
    required this.schoolType,
  });

  final String id;

  /// z.B. „5b“
  final String name;
  final int grade;

  /// Wie bei Kindern (Grundschule, Gymnasium, …) – steuert Fächer und
  /// KI-Fragen
  final String schoolType;

  factory SchoolClass.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return SchoolClass(
      id: doc.id,
      name: data['name'] as String? ?? '',
      grade: data['grade'] as int? ?? 1,
      schoolType: data['schoolType'] as String? ?? 'Grundschule',
    );
  }
}

class SchoolMember {
  const SchoolMember({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
  });

  final String uid;
  final String name;
  final String email;
  final String role;

  bool get isAdmin => role == 'admin';

  factory SchoolMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return SchoolMember(
      uid: doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'teacher',
    );
  }
}

/// QR-Karte für ein Schülergerät. Den Token gibt es nur direkt nach dem
/// Erzeugen, gespeichert wird nur sein Hash.
class StudentCard {
  const StudentCard({
    required this.studentId,
    required this.name,
    required this.className,
    required this.link,
  });

  final String studentId;
  final String name;
  final String className;
  final Uri link;
}
