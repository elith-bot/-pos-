import 'dart:ui';
import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/activation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ThemeService.init();
  runApp(const StartupApp());
}

class StartupApp extends StatefulWidget {
  const StartupApp({super.key});
  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  late final Future<bool> session = restoreSession();
  bool activationRequired = false;
  Future<bool> restoreSession() async {
    try {
      ApiService.baseUrl = SessionService.serverUrl;
      ApiService.authToken = SessionService.token;
      final license = await ApiService.businessRequest('/api/license');
      activationRequired = license['active'] != true;
      if (activationRequired) return false;
      return await ApiService.validateSession() != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: session,
    builder: (context, snapshot) => MyApp(
      isLoggedIn: snapshot.data == true,
      activationRequired: activationRequired,
      loading: snapshot.connectionState != ConnectionState.done,
    ),
  );
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
  final bool loading;
  final bool activationRequired;
  const MyApp({
    super.key,
    required this.isLoggedIn,
    this.loading = false,
    this.activationRequired = false,
  });

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
          home: loading
              ? const Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          'جارٍ الاتصال بالنظام…',
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                )
              : activationRequired
              ? const ActivationScreen()
              : isLoggedIn
              ? const MainNavigationScreen()
              : const AuthScreen(),
        );
      },
    );
  }
}
