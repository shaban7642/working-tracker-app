import 'package:intl/intl.dart';

/// Justification for an attendance day (for late arrivals, etc.)
class AttendanceJustification {
  final String? content;
  final String? attachmentUrl;

  AttendanceJustification({
    this.content,
    this.attachmentUrl,
  });

  factory AttendanceJustification.fromJson(Map<String, dynamic> json) {
    return AttendanceJustification(
      content: json['content']?.toString(),
      attachmentUrl: json['attachmentUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (content != null) 'content': content,
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    };
  }
}

/// Represents an attendance day record from the API
class AttendanceDay {
  final String id;
  final String userId;
  final DateTime day;
  final List<DateTime> intervals;
  final double totalSeconds;
  final AttendanceJustification? justification;

  AttendanceDay({
    required this.id,
    required this.userId,
    required this.day,
    required this.intervals,
    this.totalSeconds = 0,
    this.justification,
  });

  // Computed properties
  bool get hasCheckedIn => intervals.isNotEmpty;
  bool get hasCheckedOut => intervals.length > 1;
  DateTime? get checkInTime => intervals.isNotEmpty ? intervals[0] : null;
  DateTime? get checkOutTime => intervals.length > 1 ? intervals.last : null;

  String get formattedCheckIn => checkInTime != null
      ? DateFormat('h:mm a').format(checkInTime!.toLocal())
      : '--';

  String get formattedCheckOut => checkOutTime != null
      ? DateFormat('h:mm a').format(checkOutTime!.toLocal())
      : '--';

  /// Total time as Duration
  Duration get totalDuration => Duration(seconds: totalSeconds.toInt());

  /// Formatted total time (e.g., "8h 30m")
  String get formattedTotalTime {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    // Parse intervals
    final intervalsJson = json['intervals'] as List<dynamic>? ?? [];
    final intervals = intervalsJson.map((e) {
      if (e is DateTime) return e;
      return DateTime.parse(e.toString()).toLocal();
    }).toList();

    // Parse justification if present
    AttendanceJustification? justification;
    if (json['justification'] != null && json['justification'] is Map) {
      justification = AttendanceJustification.fromJson(
        json['justification'] as Map<String, dynamic>,
      );
    }

    return AttendanceDay(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      userId: json['user']?.toString() ?? '',
      day: json['day'] is DateTime
          ? json['day']
          : DateTime.parse(json['day'].toString()).toLocal(),
      intervals: intervals,
      totalSeconds: (json['totalSeconds'] as num?)?.toDouble() ?? 0,
      justification: justification,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'user': userId,
      'day': day.toIso8601String(),
      'intervals': intervals.map((e) => e.toIso8601String()).toList(),
      'totalSeconds': totalSeconds,
      if (justification != null) 'justification': justification!.toJson(),
    };
  }

  AttendanceDay copyWith({
    String? id,
    String? userId,
    DateTime? day,
    List<DateTime>? intervals,
    double? totalSeconds,
    AttendanceJustification? justification,
  }) {
    return AttendanceDay(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      day: day ?? this.day,
      intervals: intervals ?? this.intervals,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      justification: justification ?? this.justification,
    );
  }

  @override
  String toString() {
    return 'AttendanceDay(id: $id, day: $day, intervals: ${intervals.length}, totalSeconds: $totalSeconds)';
  }
}
