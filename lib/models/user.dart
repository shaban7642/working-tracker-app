import 'package:hive/hive.dart';

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
    };
  }

  // Create from API login response
  factory User.fromLoginResponse(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return User(
      id: user['id'] as String,
      email: user['email'] as String,
      name: (user['email'] as String).split('@')[0], // derive name from email
      token: json['accessToken'] as String?,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      role: user['role'] as String?,
      permissions: (user['permissions'] as List<dynamic>?)?.cast<String>(),
      additionalPermissions: (user['additionalPermissions'] as List<dynamic>?)?.cast<String>(),
      refreshToken: json['refreshToken'] as String?,
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
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.parse(json['lastLoginAt'] as String)
          : null,
      role: json['role'] as String?,
      permissions: (json['permissions'] as List<dynamic>?)?.cast<String>(),
      additionalPermissions: (json['additionalPermissions'] as List<dynamic>?)?.cast<String>(),
      refreshToken: json['refreshToken'] as String?,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, email: $email, name: $name, role: $role)';
  }
}
