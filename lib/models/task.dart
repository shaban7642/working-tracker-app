import 'package:hive/hive.dart';

part 'task.g.dart';

@HiveType(typeId: 4)
class Task extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String projectId;

  @HiveField(2)
  final String taskName;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final Duration totalDuration;

  Task({
    required this.id,
    required this.projectId,
    required this.taskName,
    required this.createdAt,
    this.totalDuration = Duration.zero,
  });

  Task copyWith({
    String? id,
    String? projectId,
    String? taskName,
    DateTime? createdAt,
    Duration? totalDuration,
  }) {
    return Task(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      taskName: taskName ?? this.taskName,
      createdAt: createdAt ?? this.createdAt,
      totalDuration: totalDuration ?? this.totalDuration,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'taskName': taskName,
      'createdAt': createdAt.toIso8601String(),
      'totalDuration': totalDuration.inSeconds,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      taskName: json['taskName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      totalDuration: Duration(seconds: json['totalDuration'] as int? ?? 0),
    );
  }

  @override
  String toString() {
    return 'Task(id: $id, projectId: $projectId, taskName: $taskName)';
  }
}
