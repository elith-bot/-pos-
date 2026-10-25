import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ThemeService {
  static const String _storageKey = 'app_cashier_theme_mode';
  
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static bool get isDark => themeModeNotifier.value == ThemeMode.dark;

  static void init() {
    try {
      if (kIsWeb) {
        final saved = html.window.localStorage[_storageKey];
        if (saved == 'light') {
          themeModeNotifier.value = ThemeMode.light;
          return;
        }
      }
    } catch (_) {}
    themeModeNotifier.value = ThemeMode.dark;
  }

  static void toggleTheme() {
    setTheme(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static void setTheme(ThemeMode mode) {
    themeModeNotifier.value = mode;
    try {
      if (kIsWeb) {
        html.window.localStorage[_storageKey] =
            mode == ThemeMode.light ? 'light' : 'dark';
      }
    } catch (_) {}
  }
}
