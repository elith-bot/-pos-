import 'local_store_native.dart' if (dart.library.html) 'local_store_web.dart';
import 'package:flutter/material.dart';

class ThemeService {
  static const String _storageKey = 'app_cashier_theme_mode';
  
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static bool get isDark => themeModeNotifier.value == ThemeMode.dark;

  static void init() {
    try {
      if (true) {
        final saved = store[_storageKey];
        if (saved == 'dark') {
          themeModeNotifier.value = ThemeMode.dark;
          return;
        }
      }
    } catch (_) {}
    // الوضع الفاتح هو الافتراضي عند أول تشغيل، مع احترام اختيار المستخدم المحفوظ.
    themeModeNotifier.value = ThemeMode.light;
  }

  static void toggleTheme() {
    setTheme(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static void setTheme(ThemeMode mode) {
    themeModeNotifier.value = mode;
    try {
      if (true) {
        store[_storageKey] =
            mode == ThemeMode.light ? 'light' : 'dark';
      }
    } catch (_) {}
  }
}
