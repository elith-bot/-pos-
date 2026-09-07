import 'package:flutter/material.dart';

class AppColors {
  // === الخلفيات والأسطح (Backgrounds & Surfaces) ===
  static const Color background = Color(0xFF0F172A);      // الخلفية الرئيسية العميقة
  static const Color surface = Color(0xFF1E293B);         // خلفية الكروت، القوائم الجانبية، والبطاقات
  static const Color border = Color(0xFF334155);          // حواف الكروت وحقول الإدخال

  // === الألوان الأساسية (Primary Colors) ===
  static const Color primarySolid = Color(0xFF0EA5E9);    // الأزرار الرئيسية المليئة
  static const Color primaryLight = Color(0xFF38BDF8);    // الأيقونات، الحواف النشطة، والنصوص البارزة

  // === نصوص (Text Colors) ===
  static const Color textWhite = Colors.white;            // النص الأساسي العريض
  static const Color textGray = Color(0xFF94A3B8);        // النصوص الفرعية والوصف
  static const Color textHint = Color(0xFF64748B);        // نصوص البحث (Placeholder)
  static const Color textDialog = Color(0xFFCBD5E1);      // نصوص مربعات الحوار (Dialogs)

  // === ألوان الحالات (State Colors) ===
  static const Color success = Color(0xFF22C55E);         // أرباح، تأكيد، مخزون جيد (نص)
  static const Color danger = Color(0xFFEF4444);          // حذف، أخطاء، إلغاء
  static const Color warning = Color(0xFFF59E0B);         // تعديل، توريد، خصم

  // === ألوان الشارات والمخزون (Badges) ===
  static const Color stockHighBg = Color(0xFF14532D);     // خلفية شارة المخزون المرتفع
  static const Color stockHighText = Color(0xFF86EFAC);   // نص شارة المخزون المرتفع
  static const Color stockLowBg = Color(0xFF7F1D1D);      // خلفية شارة المخزون المنخفض
  static const Color stockLowText = Color(0xFFFECACA);    // نص شارة المخزون المنخفض
  
  static const Color historyIcon = Color(0xFF10B981);     // لون أيقونة السجل
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
  // نصوص العناوين الكبيرة
  static const TextStyle header = TextStyle(
    color: AppColors.textWhite,
    fontWeight: FontWeight.bold,
    fontSize: AppSizes.fontHeader,
  );

  // نصوص العناوين داخل الكروت
  static const TextStyle cardTitle = TextStyle(
    color: AppColors.textWhite,
    fontWeight: FontWeight.bold,
    fontSize: AppSizes.fontTitle,
  );

  // نصوص فرعية (الأسعار، التاريخ)
  static const TextStyle subText = TextStyle(
    color: AppColors.textGray,
    fontSize: AppSizes.fontNormal,
  );

  // نصوص الأزرار الأساسية
  static const TextStyle buttonText = TextStyle(
    color: AppColors.textWhite,
    fontWeight: FontWeight.bold,
    fontSize: AppSizes.fontLarge,
  );

  // نصوص الأزرار الصغيرة في الكروت
  static const TextStyle cardButtonText = TextStyle(
    fontSize: AppSizes.fontSmall,
  );
}
