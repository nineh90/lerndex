import 'generated_task_models.dart';

/// Parameter für approvedQuestionsProvider
class ApprovedQuestionsParams {
  final String userId;
  final String childId;
  final Subject subject;

  ApprovedQuestionsParams({
    required this.userId,
    required this.childId,
    required this.subject,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApprovedQuestionsParams &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          childId == other.childId &&
          subject == other.subject;

  @override
  int get hashCode => userId.hashCode ^ childId.hashCode ^ subject.hashCode;
}
