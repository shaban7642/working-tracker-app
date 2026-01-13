import 'package:intl/intl.dart';

/// Model representing a time entry from previous days that needs task submission.
/// Used in the Pending Tasks dialog to show entries with taskSubmitted = false.
///
/// Note: Multiple entries from the same day/project may be merged by the backend,
/// in which case [entryIds] contains all the original entry IDs.
class PendingTimeEntry {
  final String id; // Primary ID (first entry or merged ID)
  final List<String> entryIds; // All entry IDs (for merged entries)
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
    required this.projectId,
    required this.projectName,
    this.projectImage,
    required this.startedAt,
    this.endedAt,
    required this.date,
    required this.duration,
    required this.taskSubmitted,
    required this.openStatus,
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

    // Parse entryIds - could be a list of strings or list of entry objects
    List<String> entryIds = [];
    if (json['entryIds'] != null && json['entryIds'] is List) {
      entryIds = (json['entryIds'] as List).map((e) {
        if (e is String) return e;
        if (e is Map) return e['_id'] as String? ?? e['id'] as String? ?? '';
        return '';
      }).where((e) => e.isNotEmpty).toList();
    }

    // Parse date - could be 'date', 'reportDate', or derive from startedAt
    DateTime date;
    if (json['date'] != null) {
      date = DateTime.parse(json['date'] as String);
    } else if (json['reportDate'] != null) {
      date = DateTime.parse(json['reportDate'] as String);
    } else {
      // Derive from startedAt
      final startedAt = DateTime.parse(json['startedAt'] as String);
      date = DateTime(startedAt.year, startedAt.month, startedAt.day);
    }

    return PendingTimeEntry(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      entryIds: entryIds,
      projectId: project?['_id'] as String? ??
          project?['id'] as String? ??
          json['projectId'] as String? ?? '',
      projectName:
          project?['name'] as String? ?? json['projectName'] as String? ?? '',
      projectImage: project?['projectImage'] as String? ??
          json['projectImage'] as String?,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] != null
          ? DateTime.parse(json['endedAt'] as String)
          : null,
      date: date,
      duration: json['duration'] as int? ?? 0,
      taskSubmitted: json['taskSubmitted'] as bool? ?? false,
      openStatus: json['openStatus'] as String? ?? 'closed',
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
