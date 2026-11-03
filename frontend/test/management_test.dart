import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/screens/employees_screen.dart';
import 'package:starter_app/screens/settings_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/services/permissions_service.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/core/app_theme.dart';

UserModel user(int id, String role) => UserModel(
  id: id,
  username: 'user$id',
  fullName: 'موظف $id',
  role: role,
  isActive: true,
  createdAt: '2026-10-30',
);
void main() {
  test('role hierarchy prevents self and upward management', () {
    ApiService.currentUser = user(1, 'admin');
    expect(appPermissions.canManage(user(2, 'cashier')), isTrue);
    expect(appPermissions.canManage(user(1, 'admin')), isFalse);
    expect(appPermissions.canManage(user(2, 'owner')), isFalse);
    ApiService.currentUser = user(1, 'cashier');
    expect(appPermissions.canViewProfit, isFalse);
    expect(appPermissions.canManageSettings, isFalse);
  });
  testWidgets('employees and settings fit narrow and desktop layouts', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        ApiService.currentUser = user(1, 'owner');
        for (final width in [390.0, 1400.0]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          for (final page in [
            const EmployeesScreen(),
            const SettingsScreen(),
          ]) {
            await tester.pumpWidget(
              MaterialApp(theme: AppTheme.lightTheme, home: page),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }
        }
      },
      () => MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('health')
                ? {
                    'server': 'online',
                    'db_type': 'sqlite',
                    'db_connected': true,
                  }
                : {
                    'users': [
                      {
                        'id': 2,
                        'username': 'cashier',
                        'full_name': 'موظف تجريبي',
                        'role': 'cashier',
                        'is_active': true,
                        'created_at': '2026-10-30',
                      },
                    ],
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
  });
  testWidgets('cashier cannot see system settings or employee management', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        ApiService.currentUser = user(1, 'cashier');
        await tester.pumpWidget(MaterialApp(home: const EmployeesScreen()));
        await tester.pumpAndSettle();
        expect(find.text('هذه الصفحة متاحة للإدارة فقط.'), findsOneWidget);
        await tester.pumpWidget(MaterialApp(home: const SettingsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('اتصال السيرفر'), findsNothing);
        expect(find.text('تغيير كلمة المرور'), findsOneWidget);
      },
      () => MockClient(
        (request) async =>
            http.Response('{"server":"online","db_connected":true}', 200),
      ),
    );
  });
}
