import 'generated_task.dart';

class GeneratedTaskResult {
  final bool success;
  final List<GeneratedTask> tasks;
  final String? imageUrl;
  final String? errorMessage;

  GeneratedTaskResult({
    required this.success,
    required this.tasks,
    this.imageUrl,
    this.errorMessage,
  });
}
