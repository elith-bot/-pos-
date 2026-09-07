import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import 'main_navigation_screen.dart';


class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _fullNameController.text.trim();

    if (username.isEmpty || password.isEmpty || (!_isLogin && fullName.isEmpty)) {
      setState(() {
        _errorMessage = 'يرجى إدخال جميع البيانات المطلوبة';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    if (_isLogin) {
      final res = await ApiService.login(username, password);
      if (mounted) {
        setState(() => _isLoading = false);
        if (res['status'] == 'success' && ApiService.currentUser != null) {
          await SessionService.saveSession(ApiService.currentUser!);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
            );
          }
        } else {

          setState(() {
            _errorMessage = res['message'] ?? 'فشل تسجيل الدخول';
          });
        }
      }
    } else {
      final res = await ApiService.register(username, password, fullName);
      if (mounted) {
        setState(() => _isLoading = false);
        if (res['status'] == 'success') {
          setState(() {
            _isLogin = true;
            _successMessage = 'تم إنشاء الحساب كـ "كاشير" بنجاح. يمكنك الآن تسجيل الدخول.';
          });
        } else {
          setState(() {
            _errorMessage = res['message'] ?? 'فشل إنشاء الحساب';
          });
        }
      }
    }
  }

  void _showOtpResetDialog() {
    final userCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool codeSent = false;
    String? dialogMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset, color: AppColors.primaryLight),
                SizedBox(width: 8),
                Text('نسيت كلمة المرور (OTP)', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dialogMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0369A1).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(dialogMsg!, style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: AppSizes.fontNormal)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'اسم المستخدم',
                      labelStyle: const TextStyle(color: AppColors.textGray),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  if (!codeSent) ...[
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid),
                      onPressed: () async {
                        if (userCtrl.text.trim().isEmpty) return;
                        final res = await ApiService.requestOtp(userCtrl.text.trim());
                        setDialogState(() {
                          if (res['status'] == 'success') {
                            codeSent = true;
                            dialogMsg = res['message'];
                          } else {
                            dialogMsg = res['message'] ?? 'خطأ في الطلب';
                          }
                        });
                      },
                      child: const Text('إرسال رمز OTP', style: TextStyle(color: Colors.white)),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: otpCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'رمز التحقق (OTP 6-digits)',
                        labelStyle: const TextStyle(color: AppColors.textGray),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newPassCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور الجديدة',
                        labelStyle: const TextStyle(color: AppColors.textGray),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                      onPressed: () async {
                        final res = await ApiService.resetPassword(
                          userCtrl.text.trim(),
                          otpCtrl.text.trim(),
                          newPassCtrl.text.trim(),
                        );
                        if (res['status'] == 'success') {
                          if (ctx.mounted) Navigator.pop(ctx);
                          setState(() {
                            _successMessage = 'تم إعادة تعيين كلمة المرور بنجاح. سجل دخولك الآن.';
                          });
                        } else {
                          setDialogState(() {
                            dialogMsg = res['message'];
                          });
                        }
                      },
                      child: const Text('حفظ كلمة المرور الجديدة', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(28),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primarySolid.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primaryLight, width: 2),
                    ),
                    child: const Icon(Icons.storefront, size: 48, color: AppColors.primaryLight),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isLogin ? 'تسجيل الدخول للنظام' : 'إنشاء حساب جديد',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.fontHuge,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isLogin ? 'أدخل اسم المستخدم وكلمة المرور' : 'سيتم إنشاء الحساب بصفة كاشير افتراضياً',
                    style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontMedium),
                  ),
                  const SizedBox(height: 20),

                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.stockLowBg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_errorMessage!,
                          style: const TextStyle(color: AppColors.stockLowText, fontSize: AppSizes.fontMedium),
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_successMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.stockHighBg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_successMessage!,
                          style: const TextStyle(color: AppColors.stockHighText, fontSize: AppSizes.fontMedium),
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (!_isLogin) ...[
                    TextField(
                      controller: _fullNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'الاسم الكامل',
                        prefixIcon: const Icon(Icons.person, color: AppColors.primaryLight),
                        labelStyle: const TextStyle(color: AppColors.textGray),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'اسم المستخدم',
                      prefixIcon: const Icon(Icons.account_circle, color: AppColors.primaryLight),
                      labelStyle: const TextStyle(color: AppColors.textGray),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock, color: AppColors.primaryLight),
                      labelStyle: const TextStyle(color: AppColors.textGray),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  if (_isLogin) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _showOtpResetDialog,
                        child: const Text('نسيت كلمة المرور؟ (OTP)',
                            style: TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontNormal)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primarySolid,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _isLogin ? 'تسجيل الدخول' : 'إنشاء الحساب',
                              style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontHeader, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _errorMessage = null;
                        _successMessage = null;
                      });
                    },
                    child: Text(
                      _isLogin ? 'ليس لديك حساب؟ أنشئ حساباً جديداً' : 'لديك حساب بالفعل؟ سجل دخولك',
                      style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontMedium),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
