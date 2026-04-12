import 'package:hive/hive.dart';

part 'project.g.dart';

@HiveType(typeId: 1)
class Project extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? description;

  @HiveField(3)
  final String? client;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final DateTime? deadline;

  @HiveField(6)
  final String status; // active, paused, completed

  @HiveField(7)
  final Duration totalTime;

  @HiveField(8)
  final DateTime? lastActiveAt;

  @HiveField(9)
  final String? projectImage;

  Project({
    required this.id,
    required this.name,
    this.description,
    this.client,
    required this.createdAt,
    this.deadline,
    this.status = 'active',
    this.totalTime = Duration.zero,
    this.lastActiveAt,
    this.projectImage,
  });

  // Copy with method for immutability
  Project copyWith({
    String? id,
    String? name,
    String? description,
    String? client,
    DateTime? createdAt,
    DateTime? deadline,
    String? status,
    Duration? totalTime,
    DateTime? lastActiveAt,
    String? projectImage,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      client: client ?? this.client,
      createdAt: createdAt ?? this.createdAt,
      deadline: deadline ?? this.deadline,
      status: status ?? this.status,
      totalTime: totalTime ?? this.totalTime,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      projectImage: projectImage ?? this.projectImage,
    );
  }

  // Convert to JSON (for API integration)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'client': client,
      'createdAt': createdAt.toIso8601String(),
      'deadline': deadline?.toIso8601String(),
      'status': status,
      'totalTime': totalTime.inSeconds,
      'lastActiveAt': lastActiveAt?.toIso8601String(),
      'projectImage': projectImage,
    };
  }

  // Create from JSON (for API integration)
  // Supports both old API format and new API format
  factory Project.fromJson(Map<String, dynamic> json) {
    // Handle different possible field names from API
    // New API uses _id, old API uses id/project_id/ProjectID
    final id = (json['_id'] ?? json['id'] ?? json['project_id'] ?? json['ProjectID'] ?? '').toString();
    final name = (json['name'] ?? json['project_name'] ?? json['ProjectName'] ?? 'Unnamed Project') as String;

    // Parse dates safely
    DateTime? parsedCreatedAt;
    DateTime? parsedDeadline;

    try {
      if (json['createdAt'] != null) {
        parsedCreatedAt = DateTime.parse(json['createdAt'] as String);
      } else if (json['created_at'] != null) {
        parsedCreatedAt = DateTime.parse(json['created_at'] as String);
      }
    } catch (e) {
      // If parsing fails, use current date
      parsedCreatedAt = DateTime.now();
    }

    try {
      if (json['deadline'] != null) {
        parsedDeadline = DateTime.parse(json['deadline'] as String);
      } else if (json['due_date'] != null) {
        parsedDeadline = DateTime.parse(json['due_date'] as String);
      }
    } catch (e) {
      // If parsing fails, leave as null
      parsedDeadline = null;
    }

    // Parse total time safely - handle different formats from API
    Duration parsedTotalTime = Duration.zero;
    try {
      // Try different possible field names and formats
      // The API may return 'duration' (today's time) or 'totalTime' (all-time total)
      if (json['duration'] != null && json['duration'] is num && (json['duration'] as num) > 0) {
        parsedTotalTime = Duration(seconds: (json['duration'] as num).toInt());
      } else if (json['todayTime'] != null && json['todayTime'] is num && (json['todayTime'] as num) > 0) {
        parsedTotalTime = Duration(seconds: (json['todayTime'] as num).toInt());
      } else if (json['totalTime'] != null) {
        parsedTotalTime = Duration(seconds: (json['totalTime'] as num).toInt());
      } else if (json['total_time'] != null) {
        parsedTotalTime = Duration(seconds: (json['total_time'] as num).toInt());
      } else if (json['TotalTime'] != null) {
        parsedTotalTime = Duration(seconds: (json['TotalTime'] as num).toInt());
      }
    } catch (e) {
      // If parsing fails, default to zero
      parsedTotalTime = Duration.zero;
    }

    // Parse lastActiveAt
    DateTime? parsedLastActiveAt;
    try {
      if (json['lastActiveAt'] != null) {
        parsedLastActiveAt = DateTime.parse(json['lastActiveAt'] as String);
      } else if (json['last_active_at'] != null) {
        parsedLastActiveAt = DateTime.parse(json['last_active_at'] as String);
      }
    } catch (e) {
      parsedLastActiveAt = null;
    }

    // Get client from new API format (createdBy user) or old format
    String? client = json['client'] as String?;
    if (client == null && json['createdBy'] != null && json['createdBy'] is Map) {
      final createdBy = json['createdBy'] as Map<String, dynamic>;
      final firstName = createdBy['firstName'] as String? ?? '';
      final lastName = createdBy['lastName'] as String? ?? '';
      client = '$firstName $lastName'.trim();
      if (client.isEmpty) client = null;
    }

    // Get district as description if no description provided (new API format)
    String? description = json['description'] as String?;
    if (description == null && json['district'] != null) {
      description = 'District: ${json['district']}';
    }

    // Get project image URL
    final projectImage = json['projectImage'] as String?;

    return Project(
      id: id,
      name: name,
      description: description,
      client: client,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      deadline: parsedDeadline,
      status: json['status'] as String? ?? 'active',
      totalTime: parsedTotalTime,
      lastActiveAt: parsedLastActiveAt,
      projectImage: projectImage,
    );
  }

  /// Extract URL string from a SignedFile object or plain string.
  /// The backend may return `{ url, cacheKey }` (SignedFile) or a plain String.
  static String? extractUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) return value['url'] as String?;
    return null;
  }

  // Create from GraphQL response (Project_Project_GetProjects items)
  factory Project.fromGraphql(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final name = (json['name'] ?? 'Unnamed Project') as String;

    // Parse description, fall back to address district
    String? description = json['description'] as String?;
    if ((description == null || description.isEmpty) && json['address'] != null && json['address'] is Map) {
      final address = json['address'] as Map<String, dynamic>;
      final district = address['district'] as String?;
      final city = address['city'] as String?;
      if (district != null && district.isNotEmpty) {
        description = city != null && city.isNotEmpty ? '$district, $city' : district;
      }
    }

    // Get client from createdBy
    String? client;
    if (json['createdBy'] != null && json['createdBy'] is Map) {
      final createdBy = json['createdBy'] as Map<String, dynamic>;
      final firstName = createdBy['firstName'] as String? ?? '';
      final lastName = createdBy['lastName'] as String? ?? '';
      client = '$firstName $lastName'.trim();
      if (client.isEmpty) client = null;
    }

    // Parse createdAt
    DateTime createdAt;
    try {
      createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now();
    } catch (e) {
      createdAt = DateTime.now();
    }

    // Map isActive to status
    final isActive = json['isActive'] as bool? ?? true;
    final status = isActive ? 'active' : 'inactive';

    // Project image - prefer thumbnail for list views (smaller, faster loading)
    final projectImage = extractUrl(json['imageThumbnailUrl']) ?? extractUrl(json['imageUrl']);

    return Project(
      id: id,
      name: name,
      description: description,
      client: client,
      createdAt: createdAt,
      status: status,
      projectImage: projectImage,
    );
  }

  @override
  String toString() {
    return 'Project(id: $id, name: $name, status: $status)';
  }
}
