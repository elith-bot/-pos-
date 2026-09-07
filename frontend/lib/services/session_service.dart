import 'dart:convert';
import 'dart:html' as html;
import '../models/user_model.dart';

class SessionService {
  static const String _sessionKey = 'app_cashier_user_session';

  static Future<void> saveSession(UserModel user) async {
    try {
      final jsonStr = json.encode({
        'id': user.id,
        'username': user.username,
        'full_name': user.fullName,
        'role': user.role,
        'is_active': user.isActive,
        'created_at': user.createdAt,
      });
      html.window.localStorage[_sessionKey] = jsonStr;
    } catch (e) {
      print('Save session error: $e');
    }
  }

  static Future<UserModel?> loadSession() async {
    try {
      final jsonStr = html.window.localStorage[_sessionKey];
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
      html.window.localStorage.remove(_sessionKey);
    } catch (e) {
      print('Clear session error: $e');
    }
  }
}
