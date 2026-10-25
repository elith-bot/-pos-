import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  bool _isLoading = true;
  String _activeDb = 'sqlite';
  bool _dbConnected = false;

  @override
  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    ThemeService.themeModeNotifier.addListener(_onThemeChanged);
    super.initState();
    _urlCtrl.text = ApiService.baseUrl;
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() => _isLoading = true);
    final health = await ApiService.checkHealth();
    if (mounted) {
      setState(() {
        _activeDb = health['db_type'] ?? 'sqlite';
        _dbConnected = health['db_connected'] ?? false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings, color: AppColors.primaryLight, size: 32),
                  const SizedBox(width: 10),
                  Text(
                    'إعدادات النظام والمظهر',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppSizes.fontHuge,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // === قسم مظهر التطبيق (Theme Mode Switcher) ===
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService.themeModeNotifier,
                builder: (context, currentMode, _) {
                  final isDark = currentMode == ThemeMode.dark;
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isDark ? Icons.dark_mode : Icons.light_mode,
                                  color: isDark ? const Color(0xFFFBBF24) : AppColors.primaryLight,
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'مظهر النظام (Theme Mode)',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: AppSizes.fontHeader,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.primaryLight),
                              ),
                              child: Text(
                                isDark ? 'الوضع الليلي نشط' : 'الوضع النهاري نشط',
                                style: TextStyle(
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppSizes.fontNormal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'اختر المظهر المريح لعينيك أثناء العمل على الكاشير وإدارة المبيعات:',
                          style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            // خيار الوضع الليلي
                            Expanded(
                              child: InkWell(
                                onTap: () => ThemeService.setTheme(ThemeMode.dark),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0F172A) : AppColors.background,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark ? AppColors.primarySolid : AppColors.border,
                                      width: isDark ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.nightlight_round, color: Color(0xFFFBBF24), size: 22),
                                      const SizedBox(width: 8),
                                      Text(
                                        'الوضع الليلي (Dark Mode)',
                                        style: TextStyle(
                                          color: isDark ? Colors.white : AppColors.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: AppSizes.fontNormal,
                                        ),
                                      ),
                                      if (isDark) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            // خيار الوضع النهاري
                            Expanded(
                              child: InkWell(
                                onTap: () => ThemeService.setTheme(ThemeMode.light),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: !isDark ? const Color(0xFFF8FAFC) : AppColors.background,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: !isDark ? AppColors.primarySolid : AppColors.border,
                                      width: !isDark ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.wb_sunny_rounded, color: Color(0xFFF59E0B), size: 22),
                                      const SizedBox(width: 8),
                                      Text(
                                        'الوضع النهاري (Light Mode)',
                                        style: TextStyle(
                                          color: !isDark ? const Color(0xFF0F172A) : AppColors.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: AppSizes.fontNormal,
                                        ),
                                      ),
                                      if (!isDark) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Server URL Box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رابط الباك إند (Backend Server URL):',
                        style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontLarge)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlCtrl,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primarySolid,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {
                        ApiService.baseUrl = _urlCtrl.text.trim();
                        _checkHealth();
                      },
                      child: const Text('حفظ رابط السيرفر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Database Switcher Box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('التبديل بين قواعد البيانات (SQLAlchemy ORM Engine):',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _dbConnected
                                ? AppColors.success.withOpacity(0.15)
                                : AppColors.danger.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'المحرك الحالي: ${_activeDb.toUpperCase()}',
                            style: TextStyle(
                              color: _dbConnected ? AppColors.stockHighText : AppColors.stockLowText,
                              fontWeight: FontWeight.bold,
                              fontSize: AppSizes.fontNormal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _activeDb == 'sqlite' ? const Color(0xFF0284C7) : AppColors.border,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.storage, color: Colors.white),
                            label: const Text('التحويل لـ SQLite', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              await ApiService.switchDatabase('sqlite');
                              _checkHealth();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _activeDb == 'mysql' ? const Color(0xFFD97706) : AppColors.border,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.dns, color: Colors.white),
                            label: const Text('التحويل لـ MySQL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              await ApiService.switchDatabase('mysql');
                              _checkHealth();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  @override
  void dispose() {
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }
}
