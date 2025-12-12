/// Represents a real-time time entry event from the Socket.IO server
class TimeEntryEvent {
  final TimeEntryEventType type;
  final String id;
  final String userId;
  final String projectId;
  final String projectName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? duration; // in seconds
  final String source; // 'desktop', 'web', 'mobile'
  final bool openStatus;

  TimeEntryEvent({
    required this.type,
    required this.id,
    required this.userId,
    required this.projectId,
    required this.projectName,
    required this.startedAt,
    this.endedAt,
    this.duration,
    required this.source,
    required this.openStatus,
  });

  /// Parse a timeEntry:started event payload
  factory TimeEntryEvent.fromStartedPayload(Map<String, dynamic> payload) {
    final project = payload['project'] as Map<String, dynamic>?;

    return TimeEntryEvent(
      type: TimeEntryEventType.started,
      id: payload['_id']?.toString() ?? '',
      userId: payload['user']?.toString() ?? '',
      projectId: project?['_id']?.toString() ?? payload['project']?.toString() ?? '',
      projectName: project?['name']?.toString() ?? '',
      startedAt: _parseDateTime(payload['startedAt']),
      source: payload['source']?.toString() ?? 'unknown',
      openStatus: payload['openStatus'] == true,
    );
  }

  /// Parse a timeEntry:ended event payload
  factory TimeEntryEvent.fromEndedPayload(Map<String, dynamic> payload) {
    final project = payload['project'] as Map<String, dynamic>?;

    return TimeEntryEvent(
      type: TimeEntryEventType.ended,
      id: payload['_id']?.toString() ?? '',
      userId: payload['user']?.toString() ?? '',
      projectId: project?['_id']?.toString() ?? payload['project']?.toString() ?? '',
      projectName: project?['name']?.toString() ?? '',
      startedAt: _parseDateTime(payload['startedAt']),
      endedAt: _parseDateTime(payload['endedAt']),
      duration: payload['duration'] is int ? payload['duration'] : null,
      source: payload['source']?.toString() ?? 'unknown',
      openStatus: payload['openStatus'] == true,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  @override
  String toString() {
    return 'TimeEntryEvent(type: $type, projectId: $projectId, projectName: $projectName, openStatus: $openStatus)';
  }
}

enum TimeEntryEventType {
  started,
  ended,
}
