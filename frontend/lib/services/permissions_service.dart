import 'api_service.dart';
import '../models/user_model.dart';

/// كلاس إدارة الصلاحيات (Permissions Service)
/// هذا الكلاس سيمثل الهيكلية الأساسية التي يمكننا تطويرها مستقبلاً 
/// لتشمل صلاحيات مخصصة لكل مستخدم أو مجموعات (Roles).
class PermissionsService {
  // تطبيق نمط Singleton ليكون متاحاً في كل مكان في التطبيق بنفس النسخة
  static final PermissionsService _instance = PermissionsService._internal();
  factory PermissionsService() => _instance;
  PermissionsService._internal();

  /// الحصول على دور المستخدم الحالي (افتراضياً كاشير إذا لم يكن مسجلاً)
  String get currentRole => ApiService.currentUser?.role ?? 'cashier';

  // ==========================================
  // إعدادات الصلاحيات (Permissions Definitions)
  // ==========================================

  // 1. هل يمكنه رؤية سعر الشراء؟
  bool get canViewPurchasePrice {
    // مستقبلاً يمكننا التحقق من صلاحيات مخصصة للمستخدم نفسه (_currentUser.customPermissions)
    // حالياً نعتمد على الدور (Role Groups)
    return ['developer', 'owner', 'admin'].contains(currentRole);
  }

  // 2. هل يمكنه رؤية الأرباح الصافية؟
  bool get canViewProfit {
    return ['developer', 'owner', 'admin'].contains(currentRole);
  }

  // 3. هل يمكنه رؤية سعر البيع؟
  bool get canViewSellingPrice {
    return true; // متاح للجميع عادة
  }

  // 4. هل يمكنه رؤية الخصم وتطبيقه؟
  bool get canViewDiscount {
    return true; // الكاشير يحتاج رؤية الخصم
  }

  // 5. هل يمكنه تعديل وحذف المنتجات؟
  bool get canManageProducts {
    return ['developer', 'owner', 'admin'].contains(currentRole);
  }
  
  // 6. هل يمكنه رؤية الإحصائيات العامة للمبيعات؟
  bool get canViewGeneralStats {
    return ['developer', 'owner', 'admin'].contains(currentRole);
  }
}

// كائن عالمي (Global Object) يمكن استخدامه مباشرة في أي شاشة
final appPermissions = PermissionsService();
