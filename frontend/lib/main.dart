import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'models/user_model.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';
import 'services/permissions_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final savedUser = await SessionService.loadSession();
  if (savedUser != null) {
    ApiService.currentUser = savedUser;
  }
  runApp(MyApp(isLoggedIn: savedUser != null));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام الكاشير والمبيعات المتكامل',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primarySolid,
          surface: AppColors.surface,
        ),
      ),
      home: isLoggedIn ? const MainNavigationScreen() : const AuthScreen(),
    );
  }
}
