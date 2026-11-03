import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/restock_history_model.dart';

class ApiService {
  static final reportsRevision = ValueNotifier<int>(0);
  static String baseUrl = 'http://127.0.0.1:5000';
  static UserModel? currentUser;
  static String? authToken;
  static String lastError = 'تعذر تنفيذ العملية. تحقق من الاتصال وحاول مجدداً.';
  static void Function()? onSessionExpired;
  static Future<http.Response> _request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final client = http.Client();
    final sentToken = url.origin == Uri.parse(baseUrl).origin
        ? authToken
        : null;
    try {
      final request = http.Request(method, url);
      request.headers.addAll({
        ...?headers,
        if (sentToken != null) 'Authorization': 'Bearer $sentToken',
      });
      if (body != null) request.body = body as String;
      final response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        try {
          lastError =
              jsonDecode(utf8.decode(response.bodyBytes))['message'] ??
              'تعذر تنفيذ العملية';
        } catch (_) {
          lastError = 'تعذر تنفيذ العملية';
        }
        if (response.statusCode == 401 &&
            sentToken != null &&
            sentToken == authToken) {
          authToken = null;
          currentUser = null;
          onSessionExpired?.call();
        }
      }
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          method != 'GET' &&
          (url.path == '/api/sales' ||
              url.path == '/api/expenses' ||
              url.path.startsWith('/api/expenses/') ||
              url.path.startsWith('/api/hr/') ||
              url.path.startsWith('/api/fixed-expenses') ||
              url.path.endsWith('/restock') ||
              url.path == '/api/switch-db')) {
        reportsRevision.value++;
      }
      return response;
    } catch (_) {
      lastError = 'لم يتم تأكيد العملية. تحقق من الاتصال ثم أعد المحاولة.';
      rethrow;
    } finally {
      client.close();
    }
  }

  static Future<http.Response> _get(Uri url, {Map<String, String>? headers}) =>
      _request('GET', url, headers: headers);
  static Future<http.Response> _post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('POST', url, headers: headers, body: body);
  static Future<http.Response> _put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('PUT', url, headers: headers, body: body);
  static Future<http.Response> _delete(
    Uri url, {
    Map<String, String>? headers,
  }) => _request('DELETE', url, headers: headers);
  static Future<UserModel?> validateSession() async {
    if (authToken == null) return null;
    try {
      final r = await _get(Uri.parse('$baseUrl/api/auth/me'));
      if (r.statusCode == 200) {
        currentUser = UserModel.fromJson(
          jsonDecode(utf8.decode(r.bodyBytes))['user'],
        );
        return currentUser;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> logout() async {
    try {
      await _post(Uri.parse('$baseUrl/api/auth/logout'));
    } catch (_) {}
    authToken = null;
    currentUser = null;
  }

  static Future<bool> resetEmployeePassword(int id, String password) async {
    try {
      final r = await _put(
        Uri.parse('$baseUrl/api/users/$id/password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'new_password': password}),
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> changePassword(String current, String next) async {
    try {
      final r = await _post(
        Uri.parse('$baseUrl/api/auth/password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'current_password': current, 'new_password': next}),
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> checkHealth({String? url}) async {
    try {
      final response = await _get(
        Uri.parse('${url ?? baseUrl}/api/health'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return {'server': 'offline', 'db_type': 'unknown', 'db_connected': false};
  }

  // --- AUTHENTICATION ---
  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'username': username, 'password': password}),
      );
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['user'] != null) {
        currentUser = UserModel.fromJson(data['user']);
        authToken = data['token'];
      }
      return data;
    } catch (e) {
      return {'status': 'error', 'message': 'تعذر الاتصال بالسيرفر: $e'};
    }
  }

  static Future<Map<String, dynamic>> register(
    String username,
    String password,
    String fullName,
  ) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'username': username,
          'password': password,
          'full_name': fullName,
        }),
      );
      return json.decode(utf8.decode(response.bodyBytes));
    } catch (e) {
      return {'status': 'error', 'message': 'تعذر الاتصال بالسيرفر: $e'};
    }
  }

  static Future<Map<String, dynamic>> requestOtp(String username) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/auth/request-otp'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'username': username}),
      );
      return json.decode(utf8.decode(response.bodyBytes));
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(
    String username,
    String code,
    String newPassword,
  ) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/auth/reset-password'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'username': username,
          'code': code,
          'new_password': newPassword,
        }),
      );
      return json.decode(utf8.decode(response.bodyBytes));
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // --- USERS / EMPLOYEES ---
  static Future<List<UserModel>> getUsers() async {
    try {
      final response = await _get(Uri.parse('$baseUrl/api/users'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['users'] != null) {
          return (data['users'] as List)
              .map((u) => UserModel.fromJson(u))
              .toList();
        }
      }
    } catch (_) {}
    throw Exception(lastError);
  }

  static Future<bool> updateUserRole(int userId, String newRole) async {
    try {
      final response = await _put(
        Uri.parse('$baseUrl/api/users/$userId/role'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'role': newRole}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggleUserActive(int userId) async {
    try {
      final response = await _put(
        Uri.parse('$baseUrl/api/users/$userId/toggle-active'),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- PRODUCTS ---
  static Future<List<ProductModel>> getProducts({
    String search = '',
    double? minPrice,
    double? maxPrice,
    int? minStock,
  }) async {
    try {
      String query =
          '$baseUrl/api/products?search=${Uri.encodeQueryComponent(search)}';
      if (minPrice != null) query += '&min_price=$minPrice';
      if (maxPrice != null) query += '&max_price=$maxPrice';
      if (minStock != null) query += '&min_stock=$minStock';

      final response = await _get(Uri.parse(query));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['products'] != null) {
          return (data['products'] as List)
              .map((p) => ProductModel.fromJson(p))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<ProductModel?> getProductByBarcode(String barcode) async {
    try {
      final response = await _get(
        Uri.parse(
          '$baseUrl/api/products/barcode/${Uri.encodeComponent(barcode)}',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['product'] != null) {
          return ProductModel.fromJson(data['product']);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> addProduct(Map<String, dynamic> productData) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/products'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(productData),
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateProduct(
    int id,
    Map<String, dynamic> productData,
  ) async {
    try {
      final response = await _put(
        Uri.parse('$baseUrl/api/products/$id'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(productData),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> restockProduct(
    int id,
    double addedQty,
    double purchasePrice, {
    double? sellingPrice,
  }) async {
    try {
      final Map<String, dynamic> bodyData = {
        'added_quantity': addedQty,
        'purchase_price': purchasePrice,
      };
      if (sellingPrice != null) {
        bodyData['selling_price'] = sellingPrice;
      }
      final response = await _post(
        Uri.parse('$baseUrl/api/products/$id/restock'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(bodyData),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<RestockHistoryModel>> getRestockHistory(
    int productId,
  ) async {
    try {
      final response = await _get(
        Uri.parse('$baseUrl/api/products/$productId/restock-history'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['history'] != null) {
          return (data['history'] as List)
              .map((h) => RestockHistoryModel.fromJson(h))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> deleteProduct(int id) async {
    try {
      final response = await _delete(Uri.parse('$baseUrl/api/products/$id'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- TABLES ---
  static Future<List<Map<String, dynamic>>> getTables() async {
    try {
      final response = await _get(Uri.parse('$baseUrl/api/tables'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['tables'] != null) {
          return List<Map<String, dynamic>>.from(data['tables']);
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> createTables(int count) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/tables'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'count': count}),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteTable(int tableId) async {
    try {
      final response = await _delete(Uri.parse('$baseUrl/api/tables/$tableId'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getTableOrder(int tableId) async {
    try {
      final response = await _get(
        Uri.parse('$baseUrl/api/tables/$tableId/order'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> saveTableOrder(
    int tableId,
    List<CartItemModel> cartItems, {
    double globalDiscount = 0,
  }) async {
    try {
      final body = {
        'global_discount': globalDiscount,
        'cashier_id': currentUser?.id,
        'items': cartItems.map((item) => item.toJson()).toList(),
      };
      final response = await _post(
        Uri.parse('$baseUrl/api/tables/$tableId/order'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(body),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- SALES ---
  static Future<bool> checkoutSale(
    List<CartItemModel> cartItems,
    String paymentMethod,
    double globalDiscount, {
    int? tableId,
    required String checkoutKey,
  }) async {
    try {
      final body = {
        'cashier_id': currentUser?.id,
        'cashier_name': currentUser?.fullName ?? 'كاشير',
        'payment_method': paymentMethod,
        'global_discount': globalDiscount,
        'table_id': tableId,
        'checkout_key': checkoutKey,
        'items': cartItems.map((item) => item.toJson()).toList(),
      };
      final response = await _post(
        Uri.parse('$baseUrl/api/sales'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(body),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getSales({
    String period = 'all',
    String? startDate,
    String? endDate,
  }) async {
    try {
      final params = <String, String>{
        'period': period,
        'tz_offset': '${DateTime.now().timeZoneOffset.inMinutes}',
      };
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      final response = await _get(
        Uri.parse('$baseUrl/api/sales').replace(queryParameters: params),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['sales'] != null) {
          return List<Map<String, dynamic>>.from(data['sales']);
        }
      }
    } catch (_) {}
    return [];
  }

  // --- EXPENSES ---
  static Future<Map<String, dynamic>> getExpenses() async {
    try {
      final response = await _get(
        Uri.parse('$baseUrl/api/expenses'),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    throw Exception(
      'تعذر تحميل المصاريف. تحقق من الاتصال بالسيرفر وحاول مجدداً.',
    );
  }

  static Future<bool> addExpense(
    String title,
    double amount,
    String category,
    String notes,
  ) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/expenses'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'title': title,
          'amount': amount,
          'category': category,
          'notes': notes,
          'created_by': currentUser?.fullName ?? 'المدير',
        }),
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteExpense(int id) async {
    try {
      final response = await _delete(Uri.parse('$baseUrl/api/expenses/$id'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- STATS ---
  static Future<Map<String, dynamic>> businessRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final response = await _request(
      method,
      Uri.parse('$baseUrl$path').replace(queryParameters: query),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw Exception(lastError);
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(response.bodyBytes)),
    );
  }

  static Future<Map<String, dynamic>> getStats({
    String period = 'all',
    String? startDate,
    String? endDate,
  }) async {
    try {
      final params = <String, String>{
        'period': period,
        'tz_offset': '${DateTime.now().timeZoneOffset.inMinutes}',
      };
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;
      final response = await _get(
        Uri.parse('$baseUrl/api/stats').replace(queryParameters: params),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {}
    throw Exception(lastError);
  }

  // --- DATABASE SWITCHER ---
  static Future<bool> switchDatabase(String dbType) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/api/switch-db'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'db_type': dbType}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
