import 'package:hive/hive.dart';
import '../core/utils/date_parsing.dart';

part 'user.g.dart';

@HiveType(typeId: 0)
class User extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String email;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final String? token; // accessToken from API

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final DateTime? lastLoginAt;

  @HiveField(6)
  final String? role;

  @HiveField(7)
  final List<String>? permissions;

  @HiveField(8)
  final List<String>? additionalPermissions;

  @HiveField(9)
  final String? refreshToken;

  @HiveField(10)
  final String? avatar;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.token,
    required this.createdAt,
    this.lastLoginAt,
    this.role,
    this.permissions,
    this.additionalPermissions,
    this.refreshToken,
    this.avatar,
  });

  // Copy with method for immutability
  User copyWith({
    String? id,
    String? email,
    String? name,
    String? token,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    String? role,
    List<String>? permissions,
    List<String>? additionalPermissions,
    String? refreshToken,
    String? avatar,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      token: token ?? this.token,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      additionalPermissions: additionalPermissions ?? this.additionalPermissions,
      refreshToken: refreshToken ?? this.refreshToken,
      avatar: avatar ?? this.avatar,
    );
  }

  // Convert to JSON (for API integration)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'token': token,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'role': role,
      'permissions': permissions,
      'additionalPermissions': additionalPermissions,
      'refreshToken': refreshToken,
      'avatar': avatar,
    };
  }

  // Create from API login response
  factory User.fromLoginResponse(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final email = user['email'] as String;
    // Build full name from firstName + lastName, fallback to email prefix
    final firstName = user['firstName'] as String?;
    final lastName = user['lastName'] as String?;
    final name = _buildFullName(firstName, lastName) ?? email.split('@')[0];
    return User(
      id: user['id'] as String,
      email: email,
      name: name,
      token: json['accessToken'] as String?,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      role: user['role'] as String?,
      permissions: (user['permissions'] as List<dynamic>?)
          ?.whereType<String>()
          .toList(),
      additionalPermissions: (user['additionalPermissions'] as List<dynamic>?)
          ?.whereType<String>()
          .toList(),
      refreshToken: json['refreshToken'] as String?,
      avatar: user['avatar'] as String?,
    );
  }

  /// Extract URL from a SignedFile object or plain string
  static String? _extractUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) return value['url'] as String?;
    return null;
  }

  /// Build full name from firstName and lastName
  static String? _buildFullName(String? firstName, String? lastName) {
    if (firstName == null && lastName == null) return null;
    if (firstName == null) return lastName;
    if (lastName == null) return firstName;
    return '$firstName $lastName';
  }

  // Create from GraphQL Employee_GetMyProfile response
  factory User.fromGraphqlProfile(
    Map<String, dynamic> profile,
    String accessToken,
    String? refreshToken,
  ) {
    final email = profile['email'] as String? ?? '';
    final firstName = profile['firstName'] as String?;
    final lastName = profile['lastName'] as String?;
    final fullName = profile['fullName'] as String? ??
        _buildFullName(firstName, lastName) ??
        email.split('@')[0];

    return User(
      id: profile['id'] as String,
      email: email,
      name: fullName,
      token: accessToken,
      refreshToken: refreshToken,
      createdAt: profile['createdAt'] != null
          ? DateTime.tryParse(profile['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastLoginAt: DateTime.now(),
      role: profile['designation'] as String?,
      permissions: null,
      additionalPermissions: null,
      avatar: _extractUrl(profile['professionalImageUrl']),
    );
  }

  // Create from JSON (for local storage)
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      token: json['token'] as String?,
      createdAt: json['createdAt'] != null
          ? parseUtcDateTime(json['createdAt'] as String)
          : DateTime.now(),
      lastLoginAt: json['lastLoginAt'] != null
          ? parseUtcDateTime(json['lastLoginAt'] as String)
          : null,
      role: json['role'] as String?,
      permissions: (json['permissions'] as List<dynamic>?)
          ?.whereType<String>()
          .toList(),
      additionalPermissions: (json['additionalPermissions'] as List<dynamic>?)
          ?.whereType<String>()
          .toList(),
      refreshToken: json['refreshToken'] as String?,
      avatar: json['avatar'] as String?,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, email: $email, name: $name, role: $role)';
  }
}
