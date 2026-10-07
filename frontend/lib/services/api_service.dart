import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/restock_history_model.dart';

class ApiService {
  static String baseUrl = 'http://127.0.0.1:5000';
  static UserModel? currentUser;

  static Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return {'server': 'offline', 'db_type': 'unknown', 'db_connected': false};
  }

  // --- AUTHENTICATION ---
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'username': username, 'password': password}),
      );
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['user'] != null) {
        currentUser = UserModel.fromJson(data['user']);
      }
      return data;
    } catch (e) {
      return {'status': 'error', 'message': 'تعذر الاتصال بالسيرفر: $e'};
    }
  }

  static Future<Map<String, dynamic>> register(String username, String password, String fullName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'username': username, 'password': password, 'full_name': fullName}),
      );
      return json.decode(utf8.decode(response.bodyBytes));
    } catch (e) {
      return {'status': 'error', 'message': 'تعذر الاتصال بالسيرفر: $e'};
    }
  }

  static Future<Map<String, dynamic>> requestOtp(String username) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/request-otp'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'username': username}),
      );
      return json.decode(utf8.decode(response.bodyBytes));
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(String username, String code, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/reset-password'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'username': username, 'code': code, 'new_password': newPassword}),
      );
      return json.decode(utf8.decode(response.bodyBytes));
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // --- USERS / EMPLOYEES ---
  static Future<List<UserModel>> getUsers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/users'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['users'] != null) {
          return (data['users'] as List).map((u) => UserModel.fromJson(u)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> updateUserRole(int userId, String newRole) async {
    try {
      final response = await http.put(
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
      final response = await http.put(Uri.parse('$baseUrl/api/users/$userId/toggle-active'));
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
      String query = '$baseUrl/api/products?search=$search';
      if (minPrice != null) query += '&min_price=$minPrice';
      if (maxPrice != null) query += '&max_price=$maxPrice';
      if (minStock != null) query += '&min_stock=$minStock';

      final response = await http.get(Uri.parse(query));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['products'] != null) {
          return (data['products'] as List).map((p) => ProductModel.fromJson(p)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<ProductModel?> getProductByBarcode(String barcode) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/products/barcode/$barcode'));
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
      final response = await http.post(
        Uri.parse('$baseUrl/api/products'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(productData),
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateProduct(int id, Map<String, dynamic> productData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/products/$id'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(productData),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> restockProduct(int id, double addedQty, double purchasePrice) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/products/$id/restock'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'added_quantity': addedQty, 'purchase_price': purchasePrice}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<RestockHistoryModel>> getRestockHistory(int productId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/products/$productId/restock-history'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['history'] != null) {
          return (data['history'] as List).map((h) => RestockHistoryModel.fromJson(h)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> deleteProduct(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/products/$id'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- TABLES ---
  static Future<List<Map<String, dynamic>>> getTables() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/tables'));
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
      final response = await http.post(
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
      final response = await http.delete(Uri.parse('$baseUrl/api/tables/$tableId'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getTableOrder(int tableId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/tables/$tableId/order'));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> saveTableOrder(int tableId, List<CartItemModel> cartItems) async {
    try {
      final body = {
        'cashier_id': currentUser?.id,
        'items': cartItems.map((item) => item.toJson()).toList(),
      };
      final response = await http.post(
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
  static Future<bool> checkoutSale(List<CartItemModel> cartItems, String paymentMethod, double globalDiscount, {int? tableId}) async {
    try {
      final body = {
        'cashier_id': currentUser?.id,
        'cashier_name': currentUser?.fullName ?? 'كاشير',
        'payment_method': paymentMethod,
        'global_discount': globalDiscount,
        'table_id': tableId,
        'items': cartItems.map((item) => item.toJson()).toList(),
      };
      final response = await http.post(
        Uri.parse('$baseUrl/api/sales'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode(body),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getSales() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/sales'));
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
      final response = await http.get(Uri.parse('$baseUrl/api/expenses'));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return {'expenses': [], 'total_amount': 0.0};
  }

  static Future<bool> addExpense(String title, double amount, String category, String notes) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/expenses'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'title': title,
          'amount': amount,
          'category': category,
          'notes': notes,
          'created_by': currentUser?.fullName ?? 'المدير'
        }),
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteExpense(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/expenses/$id'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- STATS ---
  static Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/stats'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return data['stats'] ?? {};
      }
    } catch (_) {}
    return {};
  }

  // --- DATABASE SWITCHER ---
  static Future<bool> switchDatabase(String dbType) async {
    try {
      final response = await http.post(
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
