import 'package:flutter/foundation.dart';
import 'api_service.dart';

class SystemSettingsService {
  static final revision = ValueNotifier<int>(0);
  static Map<String, dynamic> values = {};
  static bool visible(String tab) => (values['tabs'] as Map?)?[tab] != false;
  static String get businessName =>
      values['business_name'] as String? ?? 'نظام الكاشير والمبيعات';
  static void apply(Map<String, dynamic> data) {
    values = Map<String, dynamic>.from(data['settings']);
    revision.value++;
  }

  static Future<void> refresh() async {
    final data = await ApiService.businessRequest('/api/settings');
    apply(data);
  }
}
