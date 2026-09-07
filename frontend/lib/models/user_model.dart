class UserModel {
  final int id;
  final String username;
  final String fullName;
  final String role; // 'developer', 'owner', 'admin', 'cashier'
  final bool isActive;
  final String createdAt;

  UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? 'cashier',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] ?? '',
    );
  }

  String get roleArabic {
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
