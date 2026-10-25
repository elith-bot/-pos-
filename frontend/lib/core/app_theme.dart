import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class AppColors {
  static bool get isDark => ThemeService.isDark;

  // === الخلفيات والأسطح (Backgrounds & Surfaces) ===
  static Color get background =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9); // الخلفية الرئيسية

  static Color get surface =>
      isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF); // الكروت، السايدبار، والبطاقات

  static Color get surfaceVariant =>
      isDark ? const Color(0xFF162032) : const Color(0xFFF8FAFC); // خلفية فرعية خفيفة

  static Color get border =>
      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0); // الحواف والحدود

  // === الألوان الأساسية (Primary Colors) ===
  static const Color primarySolid = Color(0xFF0EA5E9); // الأزرار الرئيسية المليئة
  static Color get primaryLight =>
      isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7); // الأيقونات والحواف النشطة

  // === النصوص (Text Colors) ===
  static Color get textPrimary =>
      isDark ? Colors.white : const Color(0xFF0F172A); // النص الأساسي الرئيسي
  static Color get textWhite => textPrimary; // للتوافق التلقائي مع الكود السابق

  static Color get textSecondary =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B); // النصوص الفرعية والوصف
  static Color get textGray => textSecondary; // للتوافق التلقائي

  static Color get textHint =>
      isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8); // نصوص البحث (Placeholder)

  static Color get textDialog =>
      isDark ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B); // نصوص الحوارات

  // === ألوان ثابتة دائماً (Always Fixed) ===
  static const Color alwaysWhite = Colors.white; // نصوص الأزرار الملونة (أزرق، أحمر، أخضر)
  static const Color alwaysBlack = Colors.black;

  // === ألوان الحالات (State Colors) ===
  static const Color success = Color(0xFF22C55E); // أرباح، تأكيد، مخزون جيد
  static const Color danger = Color(0xFFEF4444);  // حذف، أخطاء، إلغاء
  static const Color warning = Color(0xFFF59E0B); // تعديل، توريد، خصم

  // === ألوان الشارات والمخزون (Badges) ===
  static Color get stockHighBg =>
      isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7);
  static Color get stockHighText =>
      isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D);

  static Color get stockLowBg =>
      isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
  static Color get stockLowText =>
      isDark ? const Color(0xFFFECACA) : const Color(0xFFB91C1C);

  static Color get historyIcon =>
      isDark ? const Color(0xFF10B981) : const Color(0xFF059669);

  // === الظلال (Shadows) ===
  static Color get cardShadow =>
      isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.06);
}

class AppSizes {
  // === أحجام الخطوط (Font Sizes) ===
  static const double fontSmall = 14.0;
  static const double fontNormal = 16.0;
  static const double fontMedium = 18.0;
  static const double fontLarge = 20.0;
  static const double fontTitle = 22.0;
  static const double fontHeader = 20.0;
  
  static const double fontXLarge = 26.0;
  static const double fontXXLarge = 28.0;
  static const double fontHuge = 32.0;

  // === مقاسات الصور والكروت (Dimensions) ===
  static const double productImageHeight = 140.0;
  static const double cardMainAxisExtent = 430.0;
  
  // === الزوايا (Border Radius) ===
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
}

class AppTextStyles {
  static TextStyle get header => TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
    fontSize: AppSizes.fontHeader,
  );

  static TextStyle get cardTitle => TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.bold,
    fontSize: AppSizes.fontTitle,
  );

  static TextStyle get subText => TextStyle(
    color: AppColors.textSecondary,
    fontSize: AppSizes.fontNormal,
  );

  static TextStyle get buttonText => const TextStyle(
    color: AppColors.alwaysWhite,
    fontWeight: FontWeight.bold,
    fontSize: AppSizes.fontLarge,
  );

  static TextStyle get cardButtonText => const TextStyle(
    fontSize: AppSizes.fontSmall,
  );
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      cardColor: const Color(0xFF1E293B),
      dividerColor: const Color(0xFF334155),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primarySolid,
        surface: Color(0xFF1E293B),
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(8.0),
        radius: const Radius.circular(10),
        interactive: true,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      cardColor: const Color(0xFFFFFFFF),
      dividerColor: const Color(0xFFE2E8F0),
      colorScheme: const ColorScheme.light(
        primary: const Color(0xFF0284C7),
        surface: Color(0xFFFFFFFF),
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        elevation: 1,
        iconTheme: IconThemeData(color: Color(0xFF0F172A)),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(8.0),
        radius: const Radius.circular(10),
        interactive: true,
      ),
    );
  }
}
