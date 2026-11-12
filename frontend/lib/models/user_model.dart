class UserModel {
  final int id;
  final String username;
  final String fullName;
  final String role; // 'developer', 'owner', 'admin', 'cashier'
  final bool isActive;
  final String createdAt;
  final Set<String>? permissions;
  final String? roleLabel;
  final int? roleRank;
  final List<Map<String, dynamic>> availableRoles;

  UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
    this.permissions,
    this.roleLabel,
    this.roleRank,
    this.availableRoles = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? 'cashier',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] ?? '',
      permissions: json['permissions'] == null ? null : Set<String>.from(json['permissions']),
      roleLabel: json['role_label'],
      roleRank: json['role_rank'],
      availableRoles: List<Map<String, dynamic>>.from(json['available_roles'] ?? []),
    );
  }

  String get roleArabic {
    if (roleLabel != null) return roleLabel!;
    switch (role) {
      case 'developer':
        return 'المطور / المبرمج';
      case 'owner':
        return 'المالك';
      case 'admin':
        return 'الادمن';
      case 'cashier':
      default:
        return 'الكاشير';
    }
  }
}
