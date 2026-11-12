import '../models/user_model.dart';
import 'api_service.dart';

class PermissionsService {
  static const builtinRoles = {
    'cashier': 'كاشير',
    'admin': 'مدير',
    'owner': 'مالك',
    'developer': 'مطور',
  };
  static const ranks = {'cashier': 0, 'admin': 1, 'owner': 2, 'developer': 3};
  static Map<String, String> get roles => {
    ...builtinRoles,
    for (final role
        in ApiService.currentUser?.availableRoles ?? <Map<String, dynamic>>[])
      '${role['id']}': '${role['name']}',
    for (final role in ApiService.roleCatalog)
      '${role['id']}': '${role['name']}',
  };
  String get currentRole => ApiService.currentUser?.role ?? '';
  bool get isActive => ApiService.currentUser?.isActive == true;
  int get rank => ApiService.currentUser?.roleRank ?? ranks[currentRole] ?? -1;
  bool has(String key) {
    if (!isActive) return false;
    final explicit = ApiService.currentUser?.permissions;
    if (explicit != null) return explicit.contains(key);
    // Compatibility for an existing session until it is refreshed.
    if (!ranks.containsKey(currentRole)) return false;
    if (key == 'roles.manage' || key == 'settings.manage') return rank >= 2;
    if (key == 'system.core') return rank == 3;
    if (key.startsWith('hr.') ||
        key.startsWith('attendance.') ||
        key.startsWith('payroll.') ||
        key.startsWith('fixed.'))
      return rank >= 2;
    if ({
      'products.view',
      'sales.create',
      'sales.discount',
      'sales.price',
      'tables.view',
      'tables.edit',
      'exports.orders',
      'exports.cart',
    }.contains(key))
      return true;
    return rank >= 1;
  }

  bool get canManageProducts => [
    'products.create',
    'products.edit',
    'products.delete',
    'products.restock',
    'stock.history',
  ].any(has);
  bool get canManageExpenses => has('expenses.view') || has('fixed.view');
  bool get canManageEmployees =>
      has('employees.view') || has('hr.view') || has('roles.manage');
  bool get canManageHR => has('hr.view');
  bool get canViewGeneralStats => has('reports.view');
  bool get canViewPurchasePrice => has('financial.costs');
  bool get canViewProfit => has('financial.profit');
  bool get canViewSellingPrice => isActive;
  bool get canViewDiscount => isActive;
  bool get canManageSettings => has('settings.manage');
  bool canManage(UserModel user) =>
      isActive &&
      user.id != ApiService.currentUser?.id &&
      rank > (user.roleRank ?? ranks[user.role] ?? 99) &&
      (user.permissions == null || user.permissions!.every(has));
  List<String> get assignableRoles => roles.keys.where((role) {
    final descriptor = ApiService.roleCatalog
        .where((r) => r['id'] == role)
        .firstOrNull;
    final targetRank = descriptor?['rank'] as int? ?? ranks[role] ?? 1;
    final permissions = descriptor?['permissions'] as List?;
    return rank > targetRank &&
        (permissions == null || permissions.every((p) => has('$p')));
  }).toList();
}

final appPermissions = PermissionsService();
