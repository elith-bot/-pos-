import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';

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
  void initState() {
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
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.settings, color: AppColors.primaryLight, size: 32),
                  SizedBox(width: 10),
                  Text('إعدادات النظام وقاعدة البيانات',
                      style: TextStyle(color: Colors.white, fontSize: AppSizes.fontHuge, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),

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
                    const Text('رابط الباك إند (Backend Server URL):',
                        style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontLarge)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid),
                      onPressed: () {
                        ApiService.baseUrl = _urlCtrl.text.trim();
                        _checkHealth();
                      },
                      child: const Text('حفظ رابط السيرفر', style: TextStyle(color: Colors.white)),
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
                  border: Border.all(color: AppColors.primaryLight.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('التبديل بين قواعد البيانات (SQLAlchemy ORM Engine):',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _dbConnected
                                ? AppColors.success.withOpacity(0.2)
                                : AppColors.danger.withOpacity(0.2),
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
                            label: const Text('التحويل لـ SQLite', style: TextStyle(color: Colors.white)),
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
                            label: const Text('التحويل لـ MySQL', style: TextStyle(color: Colors.white)),
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
}
