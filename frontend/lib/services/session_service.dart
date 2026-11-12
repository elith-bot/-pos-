import 'dart:convert';
import 'local_store_native.dart' if (dart.library.html) 'local_store_web.dart';
import '../models/user_model.dart';

class SessionService {
  static const String _sessionKey = 'app_cashier_user_session';

  static String? get token => store['app_cashier_token'];
  static String get serverUrl => const bool.fromEnvironment('POS_PACKAGED')
      ? localServer
      : store['app_cashier_server'] ?? 'http://127.0.0.1:5000';
  static void saveServerUrl(String url) =>
      store['app_cashier_server'] = url;

  static Future<void> saveSession(UserModel user, {String? token}) async {
    try {
      final jsonStr = json.encode({
        'id': user.id,
        'username': user.username,
        'full_name': user.fullName,
        'role': user.role,
        'is_active': user.isActive,
        'created_at': user.createdAt,
      });
      store[_sessionKey] = jsonStr;
      if (token != null) store['app_cashier_token'] = token;
    } catch (e) {
      print('Save session error: $e');
    }
  }

  static Future<UserModel?> loadSession() async {
    try {
      final jsonStr = store[_sessionKey];
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final data = json.decode(jsonStr);
        return UserModel.fromJson(data);
      }
    } catch (e) {
      print('Load session error: $e');
    }
    return null;
  }

  static Future<void> clearSession() async {
    try {
      store.remove(_sessionKey);
      store.remove('app_cashier_token');
    } catch (e) {
      print('Clear session error: $e');
    }
  }
}
