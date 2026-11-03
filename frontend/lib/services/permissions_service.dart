import '../models/user_model.dart';
import 'api_service.dart';

class PermissionsService {
  static const roles = {
    'cashier': 'كاشير',
    'admin': 'مدير',
    'owner': 'مالك',
    'developer': 'مطور',
  };
  static const ranks = {'cashier': 0, 'admin': 1, 'owner': 2, 'developer': 3};
  String get currentRole => ApiService.currentUser?.role ?? '';
  bool get isActive => ApiService.currentUser?.isActive == true;
  bool get canManageProducts => isActive && (ranks[currentRole] ?? -1) >= 1;
  bool get canManageExpenses => canManageProducts;
  bool get canManageEmployees => canManageProducts;
  bool get canManageHR => isActive && (ranks[currentRole] ?? -1) >= 2;
  bool get canViewGeneralStats => canManageProducts;
  bool get canViewPurchasePrice => canManageProducts;
  bool get canViewProfit => canManageProducts;
  bool get canViewSellingPrice => isActive;
  bool get canViewDiscount => isActive;
  bool get canManageSettings => isActive && (ranks[currentRole] ?? -1) >= 2;
  bool canManage(UserModel user) =>
      isActive &&
      user.id != ApiService.currentUser?.id &&
      (ranks[currentRole] ?? -1) > (ranks[user.role] ?? 99);
  List<String> get assignableRoles => roles.keys
      .where((role) => (ranks[role] ?? 99) < (ranks[currentRole] ?? -1))
      .toList();
}

final appPermissions = PermissionsService();
