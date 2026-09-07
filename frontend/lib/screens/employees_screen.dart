import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  bool _isLoading = true;
  List<UserModel> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final users = await ApiService.getUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  void _changeRole(UserModel user) {
    String selectedRole = user.role;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تغيير دور الموظف: ${user.fullName}', style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: selectedRole,
                  dropdownColor: AppColors.background,
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'developer', child: Text('المطور / المبرمج (صلاحيات مطلقة)')),
                    DropdownMenuItem(value: 'owner', child: Text('المالك (إدارة كل الأدوار عدا المطور)')),
                    DropdownMenuItem(value: 'admin', child: Text('الادمن (إدارة الكاشير والمخزن والصرفيات)')),
                    DropdownMenuItem(value: 'cashier', child: Text('الكاشير (صلاحيات نقطة البيع فقط)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedRole = val);
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid),
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.updateUserRole(user.id, selectedRole);
              _loadUsers();
            },
            child: const Text('تأكيد التغيير', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Banner
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.badge, color: AppColors.primaryLight, size: 32),
                      SizedBox(width: 10),
                      Text('إدارة الموظفين والأدوار',
                          style: TextStyle(color: Colors.white, fontSize: AppSizes.fontHuge, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.refresh, color: AppColors.primaryLight), onPressed: _loadUsers),
                ],
              ),
              const SizedBox(height: 20),

              // Users List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                    : _users.isEmpty
                        ? const Center(child: Text('لا يوجد موظفون مسجلون', style: TextStyle(color: AppColors.textGray)))
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (ctx, idx) {
                              final user = _users[idx];
                              return Card(
                                color: AppColors.surface,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: AppColors.border),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.background,
                                    child: Icon(
                                      user.role == 'developer'
                                          ? Icons.code
                                          : user.role == 'owner'
                                              ? Icons.workspace_premium
                                              : user.role == 'admin'
                                                  ? Icons.admin_panel_settings
                                                  : Icons.person,
                                      color: AppColors.primaryLight,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(user.fullName,
                                          style: const TextStyle(
                                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader)),
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0369A1).withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: AppColors.primaryLight),
                                        ),
                                        child: Text(user.roleArabic,
                                            style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: AppSizes.fontNormal)),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text('اسم المستخدم: ${user.username} • تاريخ التسجيل: ${user.createdAt}',
                                      style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.border),
                                        icon: const Icon(Icons.manage_accounts, size: 16, color: Colors.white),
                                        label: const Text('تغيير الدور', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal)),
                                        onPressed: () => _changeRole(user),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: Icon(
                                          user.isActive ? Icons.check_circle : Icons.block,
                                          color: user.isActive ? AppColors.success : AppColors.danger,
                                        ),
                                        onPressed: () async {
                                          await ApiService.toggleUserActive(user.id);
                                          _loadUsers();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
