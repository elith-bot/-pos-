import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/theme_service.dart';
import 'pos_screen.dart';

import 'expenses_screen.dart';
import 'analytics_screen.dart';
import 'employees_screen.dart';
import 'settings_screen.dart';
import 'auth_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    ThemeService.themeModeNotifier.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ApiService.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        title: Row(
          children: [
            Icon(Icons.point_of_sale, color: AppColors.primaryLight, size: 26),
            const SizedBox(width: 10),
            Text(
              'نظام الكاشير والمبيعات المتكامل',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: AppSizes.fontXLarge),
            ),
            const SizedBox(width: 16),
            if (currentUser != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryLight),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 14, color: AppColors.primaryLight),
                    const SizedBox(width: 4),
                    Text(
                      '${currentUser.fullName} (${currentUser.roleArabic})',
                      style: TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService.themeModeNotifier,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return Tooltip(
                message: isDark ? 'التحويل للوضع النهاري (Light Mode)' : 'التحويل للوضع الليلي (Dark Mode)',
                child: IconButton(
                  icon: Icon(
                    isDark ? Icons.light_mode : Icons.dark_mode_outlined,
                    color: isDark ? const Color(0xFFFBBF24) : AppColors.primaryLight,
                    size: 22,
                  ),
                  onPressed: () {
                    ThemeService.toggleTheme();
                  },
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.danger),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              await SessionService.clearSession();
              ApiService.currentUser = null;
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          indicatorWeight: 3,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: AppColors.textGray,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
          tabs: const [
            Tab(icon: Icon(Icons.grid_view), text: 'الرئيسية (المنتجات والطلبات)'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'الصرفيات'),
            Tab(icon: Icon(Icons.bar_chart), text: 'الإحصائيات'),
            Tab(icon: Icon(Icons.badge), text: 'الموظفين'),
            Tab(icon: Icon(Icons.settings), text: 'الإعدادات'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          PosScreen(),
          ExpensesScreen(),
          AnalyticsScreen(),
          EmployeesScreen(),
          SettingsScreen(),
        ],
      ),
    );
  }
}
