import 'package:intl/intl.dart';
import '../core/utils/date_parsing.dart';
import 'project.dart';

/// Model representing a DailyProjectWork record from previous days that needs task submission.
/// Used in the Pending Tasks dialog to show entries with no tasks.
class PendingTimeEntry {
  final String id; // DailyProjectWork ID
  final List<String> entryIds; // All entry IDs (for merged entries)
  final String? dailyProjectWorkId; // DailyProjectWork ID for task creation
  final String projectId;
  final String projectName;
  final String? projectImage;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime date; // The date of the entry (for task fetching)
  final int duration; // Duration in seconds
  final bool taskSubmitted;
  final String openStatus;

  const PendingTimeEntry({
    required this.id,
    this.entryIds = const [],
    this.dailyProjectWorkId,
    required this.projectId,
    required this.projectName,
    this.projectImage,
    required this.startedAt,
    this.endedAt,
    required this.date,
    this.duration = 0,
    this.taskSubmitted = false,
    this.openStatus = 'closed',
  });

  /// Get all entry IDs (returns [id] if entryIds is empty)
  List<String> get allEntryIds => entryIds.isNotEmpty ? entryIds : [id];

  /// Get the date formatted as YYYY-MM-DD for API calls
  String get dateForApi {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Returns duration formatted as "2h 30m" or "45m" for less than an hour
  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '< 1m';
    }
  }

  /// Returns date formatted as "Dec 28, 2025"
  String get formattedDate {
    return DateFormat('MMM d, yyyy').format(startedAt);
  }

  /// Returns time range formatted as "09:00 AM - 12:00 PM"
  String get formattedTimeRange {
    final startFormatted = DateFormat('hh:mm a').format(startedAt);
    if (endedAt != null) {
      final endFormatted = DateFormat('hh:mm a').format(endedAt!);
      return '$startFormatted - $endFormatted';
    }
    return '$startFormatted - In Progress';
  }

  /// Returns the Duration object
  Duration get durationAsDuration => Duration(seconds: duration);

  PendingTimeEntry copyWith({
    String? id,
    List<String>? entryIds,
    String? dailyProjectWorkId,
    String? projectId,
    String? projectName,
    String? projectImage,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? date,
    int? duration,
    bool? taskSubmitted,
    String? openStatus,
  }) {
    return PendingTimeEntry(
      id: id ?? this.id,
      entryIds: entryIds ?? this.entryIds,
      dailyProjectWorkId: dailyProjectWorkId ?? this.dailyProjectWorkId,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      projectImage: projectImage ?? this.projectImage,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      date: date ?? this.date,
      duration: duration ?? this.duration,
      taskSubmitted: taskSubmitted ?? this.taskSubmitted,
      openStatus: openStatus ?? this.openStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'entryIds': entryIds,
      'project': {
        '_id': projectId,
        'name': projectName,
        'projectImage': projectImage,
      },
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'date': date.toIso8601String(),
      'duration': duration,
      'taskSubmitted': taskSubmitted,
      'openStatus': openStatus,
    };
  }

  factory PendingTimeEntry.fromJson(Map<String, dynamic> json) {
    // Handle both nested project object and flat structure
    final project = json['project'] as Map<String, dynamic>?;
    final attendance = json['attendance'] as Map<String, dynamic>?;

    final id = json['_id'] as String? ?? json['id'] as String? ?? '';

    // Parse date from attendance.date, or fallback to createdAt
    DateTime date;
    if (attendance != null && attendance['date'] != null) {
      date = parseUtcDateTime(attendance['date'] as String);
    } else if (json['createdAt'] != null) {
      final createdAt = parseUtcDateTime(json['createdAt'] as String);
      date = DateTime(createdAt.year, createdAt.month, createdAt.day);
    } else {
      date = DateTime.now();
    }

    return PendingTimeEntry(
      id: id,
      dailyProjectWorkId: id, // The ID is the DailyProjectWork ID itself
      projectId: project?['_id'] as String? ??
          project?['id'] as String? ??
          json['projectId'] as String? ?? '',
      projectName:
          project?['name'] as String? ?? json['projectName'] as String? ?? '',
      projectImage: project?['projectImage'] as String? ??
          Project.extractUrl(project?['imageUrl']) ??
          json['projectImage'] as String?,
      startedAt: date,
      date: date,
    );
  }

  @override
  String toString() {
    return 'PendingTimeEntry(id: $id, project: $projectName, date: $formattedDate, duration: $formattedDuration, taskSubmitted: $taskSubmitted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PendingTimeEntry && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
