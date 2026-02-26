import 'package:cloud_firestore/cloud_firestore.dart';

class GeneratedTask {
  final String question;
  final String solution;
  final String difficulty; // easy, medium, hard
  final String topic;

  GeneratedTask({
    required this.question,
    required this.solution,
    required this.difficulty,
    required this.topic,
  });

  factory GeneratedTask.fromJson(Map<String, dynamic> json) {
    return GeneratedTask(
      question: json['question'] ?? '',
      solution: json['solution'] ?? '',
      difficulty: json['difficulty'] ?? 'medium',
      topic: json['topic'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'question': question,
      'solution': solution,
      'difficulty': difficulty,
      'topic': topic,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
