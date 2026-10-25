import 'dart:ui';
import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'models/user_model.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'services/permissions_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ThemeService.init();
  final savedUser = await SessionService.loadSession();
  if (savedUser != null) {
    ApiService.currentUser = savedUser;
  }
  runApp(MyApp(isLoggedIn: savedUser != null));
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'نظام الكاشير والمبيعات المتكامل',
          debugShowCheckedModeBanner: false,
          scrollBehavior: AppScrollBehavior(),
          themeMode: themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: isLoggedIn ? const MainNavigationScreen() : const AuthScreen(),
        );
      },
    );
  }
}
