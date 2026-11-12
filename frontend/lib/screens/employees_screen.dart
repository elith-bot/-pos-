import 'package:flutter/material.dart';
import '../services/permissions_service.dart';
import 'hr_screen.dart';
import 'accounts_screen.dart';
import 'roles_screen.dart';
export 'accounts_screen.dart' show AccountsScreen;

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  @override
  Widget build(BuildContext context) {
    if (!appPermissions.canManageEmployees)
      return const Center(child: Text('لا توجد صلاحية لعرض الموظفين.'));
    return Column(
      children: [
        if (appPermissions.has('roles.manage'))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('إنشاء دور وإدارة الصلاحيات'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RolesScreen()),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
        Expanded(
          child: appPermissions.canManageHR
              ? const HrScreen()
              : const AccountsScreen(),
        ),
      ],
    );
  }
}
