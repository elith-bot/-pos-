import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/permissions_service.dart';
import '../services/theme_service.dart';
import 'pos_screen.dart';
import 'expenses_screen.dart';
import 'analytics_screen.dart';
import 'employees_screen.dart';
import 'settings_screen.dart';
import 'auth_screen.dart';
import 'hr_screen.dart';
import 'exports_screen.dart';
import 'activation_screen.dart';
import 'support_screen.dart';
import '../services/system_settings_service.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final _posKey = GlobalKey<PosScreenState>();
  final Set<int> _visited = {0};
  int _selected = 0;
  bool _navigating = false;
  late final List<(String, IconData, Widget)> _pages;
  @override
  void initState() {
    super.initState();
    _pages = [
      if (appPermissions.has('products.view') ||
          appPermissions.has('tables.view'))
        ('المبيعات والطاولات', Icons.point_of_sale, PosScreen(key: _posKey)),
      if (appPermissions.canManageExpenses)
        (
          'المصاريف',
          Icons.account_balance_wallet_outlined,
          const ExpensesScreen(),
        ),
      if (appPermissions.canViewGeneralStats)
        ('الإحصائيات', Icons.bar_chart, const AnalyticsScreen()),
      if (appPermissions.canManageEmployees)
        ('الموظفون', Icons.badge_outlined, const EmployeesScreen()),
      ('الإعدادات', Icons.settings_outlined, const SettingsScreen()),
    ];
    ThemeService.themeModeNotifier.addListener(_themeChanged);
    ApiService.onSessionExpired = _expired;
    ApiService.onLicenseRequired = _licenseRequired;
    SystemSettingsService.revision.addListener(_settingsChanged);
    SystemSettingsService.refresh().catchError((_) {});
  }

  String _tabKey(Widget page) => page is PosScreen
      ? 'sales'
      : page is ExpensesScreen
      ? 'expenses'
      : page is AnalyticsScreen
      ? 'analytics'
      : page is EmployeesScreen
      ? 'employees'
      : 'settings';
  List<int> get _visible => [
    for (var i = 0; i < _pages.length; i++)
      if (SystemSettingsService.visible(_tabKey(_pages[i].$3))) i,
  ];
  void _settingsChanged() {
    if (!mounted) return;
    setState(() {
      if (!_visible.contains(_selected)) {
        _selected = _pages.length - 1;
        _visited.add(_selected);
      }
    });
  }

  void _licenseRequired() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ActivationScreen()),
      (_) => false,
    );
  }

  void _themeChanged() {
    if (mounted) setState(() {});
  }

  void _expired() async {
    await SessionService.clearSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('انتهت الجلسة أو تغيرت صلاحياتك. سجل الدخول مجدداً.'),
      ),
    );
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    ThemeService.themeModeNotifier.removeListener(_themeChanged);
    ApiService.onSessionExpired = null;
    ApiService.onLicenseRequired = null;
    SystemSettingsService.revision.removeListener(_settingsChanged);
    super.dispose();
  }

  Future<void> _select(int index) async {
    if (_navigating || index == _selected) return;
    _navigating = true;
    final saved = await _posKey.currentState?.prepareToLeave() ?? true;
    _navigating = false;
    if (!mounted || !saved) return;
    setState(() {
      _selected = index;
      _visited.add(index);
    });
  }

  Future<void> _logout() async {
    if (_navigating) return;
    if (!(await _posKey.currentState?.prepareToLeave() ?? true) || !mounted)
      return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        content: const Text(
          'طلبات الطاولات محفوظة. سلة البيع المباشر غير المكتملة ستُترك عند تسجيل الخروج.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ApiService.logout();
    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final visible = _visible;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compact
                      ? _pages[_selected].$1
                      : SystemSettingsService.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 17 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${ApiService.currentUser?.fullName ?? ''} • ${ApiService.currentUser?.roleArabic ?? ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              if (appPermissions.canManageSettings)
              IconButton(
                tooltip: 'الدعم الفني والصيانة',
                icon: const Icon(Icons.headset_mic_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SupportScreen()),
                ),
              ),
              IconButton(
                tooltip: 'الملفات المصدّرة',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExportsScreen()),
                ),
              ),
              IconButton(
                tooltip: 'عقدي وشروط العمل',
                icon: const Icon(Icons.description_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyContractScreen()),
                ),
              ),
              IconButton(
                tooltip: 'تبديل المظهر',
                onPressed: ThemeService.toggleTheme,
                icon: Icon(
                  ThemeService.isDark
                      ? Icons.light_mode
                      : Icons.dark_mode_outlined,
                ),
              ),
              IconButton(
                tooltip: 'تسجيل الخروج',
                onPressed: _logout,
                icon: const Icon(Icons.logout),
              ),
            ],
            bottom: compact
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(58),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final i in visible)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: i == _selected
                                      ? AppColors.primaryLight.withValues(
                                          alpha: .12,
                                        )
                                      : Colors.transparent,
                                ),
                                onPressed: () => _select(i),
                                icon: Icon(_pages[i].$2),
                                label: Text(_pages[i].$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          bottomNavigationBar: compact && visible.length > 1
              ? NavigationBar(
                  selectedIndex: visible.indexOf(_selected),
                  onDestinationSelected: (index) => _select(visible[index]),
                  height: 68,
                  backgroundColor: AppColors.surface,
                  indicatorColor: AppColors.primaryLight.withValues(alpha: .12),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    for (final i in visible)
                      NavigationDestination(
                        icon: Icon(_pages[i].$2),
                        label: _pages[i].$3 is PosScreen
                            ? 'المبيعات'
                            : _pages[i].$1,
                      ),
                  ],
                )
              : null,
          body: IndexedStack(
            index: _selected,
            children: [
              for (var i = 0; i < _pages.length; i++)
                TickerMode(
                  enabled: i == _selected,
                  child: _visited.contains(i)
                      ? (_pages[i].$3 is AnalyticsScreen
                            ? AnalyticsScreen(isActive: i == _selected)
                            : _pages[i].$3)
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    ),
  );
}
