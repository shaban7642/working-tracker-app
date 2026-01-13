/// Model representing a task from daily reports API.
/// Used for displaying and managing tasks associated with time entries.
class ReportTask {
  final String id;
  final String? reportId;
  final String userId;
  final DateTime reportDate;
  final String projectId;
  final String taskName;
  final String taskDescription;
  final List<String> taskAttachments;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ReportTask({
    required this.id,
    this.reportId,
    required this.userId,
    required this.reportDate,
    required this.projectId,
    required this.taskName,
    required this.taskDescription,
    this.taskAttachments = const [],
    this.createdAt,
    this.updatedAt,
  });

  ReportTask copyWith({
    String? id,
    String? reportId,
    String? userId,
    DateTime? reportDate,
    String? projectId,
    String? taskName,
    String? taskDescription,
    List<String>? taskAttachments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReportTask(
      id: id ?? this.id,
      reportId: reportId ?? this.reportId,
      userId: userId ?? this.userId,
      reportDate: reportDate ?? this.reportDate,
      projectId: projectId ?? this.projectId,
      taskName: taskName ?? this.taskName,
      taskDescription: taskDescription ?? this.taskDescription,
      taskAttachments: taskAttachments ?? this.taskAttachments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'reportId': reportId,
      'userId': userId,
      'reportDate': reportDate.toIso8601String(),
      'projectId': projectId,
      'taskName': taskName,
      'taskDescription': taskDescription,
      'taskAttachments': taskAttachments,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory ReportTask.fromJson(Map<String, dynamic> json) {
    // Handle task data that might be nested in a dailyReport response
    // or directly as a task object
    final taskData = json['task'] as Map<String, dynamic>? ?? json;

    // Parse attachments - could be list of strings or list of objects
    // API may use 'taskAttachments' or 'images' field
    List<String> attachments = [];
    final rawAttachments = taskData['taskAttachments'] ?? taskData['images'];
    if (rawAttachments != null) {
      if (rawAttachments is List) {
        attachments = rawAttachments.map((e) {
          if (e is String) return e;
          if (e is Map) return e['url'] as String? ?? e['path'] as String? ?? '';
          return '';
        }).where((e) => e.isNotEmpty).toList();
      }
    }

    // Parse projectId - could be string, object with _id, or 'project' object
    String projectId;
    final rawProjectId = taskData['projectId'] ?? taskData['project'];
    if (rawProjectId is String) {
      projectId = rawProjectId;
    } else if (rawProjectId is Map) {
      projectId = rawProjectId['_id'] as String? ?? rawProjectId['id'] as String? ?? '';
    } else {
      projectId = '';
    }

    // Extract reportId - could be in taskData directly or in parent json
    // Priority: taskData.reportId > taskData.dailyReportId > json.reportId
    String? reportId;
    if (taskData['reportId'] != null) {
      final rid = taskData['reportId'];
      reportId = rid is String ? rid : (rid is Map ? (rid['_id'] ?? rid['id']) as String? : null);
    } else if (taskData['dailyReportId'] != null) {
      final rid = taskData['dailyReportId'];
      reportId = rid is String ? rid : (rid is Map ? (rid['_id'] ?? rid['id']) as String? : null);
    } else if (json['reportId'] != null && json['reportId'] != taskData['_id']) {
      // Only use json reportId if it's different from the task id
      reportId = json['reportId'] as String?;
    } else if (json['dailyReportId'] != null) {
      reportId = json['dailyReportId'] as String?;
    }

    // Handle report field which may contain the reportId
    if (reportId == null && taskData['report'] != null) {
      final report = taskData['report'];
      if (report is String) {
        reportId = report;
      } else if (report is Map) {
        reportId = report['_id'] as String? ?? report['id'] as String?;
      }
    }

    return ReportTask(
      id: taskData['_id'] as String? ?? taskData['id'] as String? ?? '',
      reportId: reportId,
      userId: taskData['userId'] as String? ?? json['userId'] as String? ?? '',
      reportDate: _parseDate(taskData['reportDate'] ?? json['reportDate']),
      projectId: projectId,
      // Handle both taskName and title fields (API uses 'title', we map to taskName)
      taskName: taskData['taskName'] as String? ?? taskData['title'] as String? ?? '',
      // Handle both taskDescription and description fields
      taskDescription: taskData['taskDescription'] as String? ?? taskData['description'] as String? ?? '',
      taskAttachments: attachments,
      createdAt: taskData['createdAt'] != null
          ? DateTime.tryParse(taskData['createdAt'] as String)
          : null,
      updatedAt: taskData['updatedAt'] != null
          ? DateTime.tryParse(taskData['updatedAt'] as String)
          : null,
    );
  }

  static DateTime _parseDate(dynamic date) {
    if (date == null) return DateTime.now();
    if (date is DateTime) return date;
    if (date is String) return DateTime.tryParse(date) ?? DateTime.now();
    return DateTime.now();
  }

  @override
  String toString() {
    return 'ReportTask(id: $id, taskName: $taskName, projectId: $projectId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReportTask && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
