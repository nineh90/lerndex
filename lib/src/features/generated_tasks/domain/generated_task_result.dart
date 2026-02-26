import '../data/generated_task_models.dart';

class GeneratedTaskResult {
  final bool success;
  final List<GeneratedQuestion> questions;
  final String? imageUrl;
  final String? errorMessage;

  GeneratedTaskResult({
    required this.success,
    required this.questions,
    this.imageUrl,
    this.errorMessage,
  });
}
