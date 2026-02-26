import '../../auth/domain/child_model.dart';

/// Parameter-Klasse für den kombinierten Quiz-Session-Provider
class CombinedQuizParams {
  final String userId;
  final String childId;
  final ChildModel child;
  final String subject;
  final int questionCount;

  CombinedQuizParams({
    required this.userId,
    required this.childId,
    required this.child,
    required this.subject,
    this.questionCount = 5,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedQuizParams &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          childId == other.childId &&
          subject == other.subject &&
          questionCount == other.questionCount;

  @override
  int get hashCode =>
      userId.hashCode ^
      childId.hashCode ^
      subject.hashCode ^
      questionCount.hashCode;
}
