/// 用户模型
class User {
  final int id;
  final String username;
  final String email;
  final String? displayName;
  final String role;
  final String status;
  final bool twoFactorEnabled;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.displayName,
    required this.role,
    required this.status,
    this.twoFactorEnabled = false,
    this.createdAt,
    this.lastLoginAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'],
      role: json['role'] ?? 'user',
      status: json['status'] ?? 'active',
      twoFactorEnabled: json['two_factor_enabled'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'display_name': displayName,
      'role': role,
      'status': status,
      'two_factor_enabled': twoFactorEnabled,
    };
  }

  bool get isAdmin => role == 'admin';
}
