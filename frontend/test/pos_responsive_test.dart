import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/core/app_theme.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/screens/pos_screen.dart';
import 'package:starter_app/screens/main_navigation_screen.dart';
import 'package:starter_app/screens/analytics_screen.dart';
import 'package:starter_app/screens/expenses_screen.dart';
import 'package:starter_app/screens/settings_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/services/theme_service.dart';

const product = {
  'id': 1,
  'name': 'شوكولاتة جالاكسي سادة',
  'category': 'حلويات',
  'selling_price': 1500,
  'purchase_price': 1000,
  'unit_profit': 500,
  'stock_quantity': 100,
};

void main() {
  final savedOrders = <Map<String, dynamic>>[];
  var failSave = false;
  Map<String, dynamic>? snapshot;
  http.Response response(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  MockClient client() => MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/products'))
      return response({
        'products': [product],
      });
    if (path.endsWith('/tables'))
      return response({
        'tables': [
          {
            'id': 1,
            'name': 'طاولة 1',
            'table_number': 1,
            'is_active': snapshot != null,
            'total_price': 1500,
          },
          {'id': 2, 'name': 'طاولة 2', 'table_number': 2, 'is_active': false},
        ],
      });
    if (path.endsWith('/order')) {
      if (request.method == 'POST') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        savedOrders.add(payload);
        if (failSave) return response({'error': 'تعذر الحفظ'}, 500);
        snapshot = payload;
        return response({'success': true});
      }
      return response({
        'has_order': snapshot != null,
        if (snapshot != null) 'order': {'cart_state': snapshot},
      });
    }
    if (path.endsWith('/health'))
      return response({
        'server': 'online',
        'db_connected': true,
        'db_type': 'sqlite',
      });
    if (path.endsWith('/expenses'))
      return response({
        'expenses': [
          {
            'id': 1,
            'title': 'فاتورة الكهرباء',
            'amount': 1000,
            'category': 'خدمات',
            'created_by': 'المدير',
            'created_at': '2026-10-31 10:00:00',
          },
        ],
      });
    return response({});
  });

  testWidgets('mobile report sections and expandable settings stay reachable', (
    tester,
  ) async {
    await http.runWithClient(() async {
      for (final width in [320.0, 390.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 850);
        for (final entry in [
          (
            const AnalyticsScreen(),
            ['الملخص', 'الرسوم والدفع', 'المنتجات والطلبات'],
          ),
          (const ExpensesScreen(), ['السجل', 'الملخص', 'التصنيفات']),
        ]) {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.lightTheme, home: entry.$1),
          );
          await tester.pumpAndSettle();
          for (final label in entry.$2) {
            final chip = find.widgetWithText(ChoiceChip, label);
            await tester.ensureVisible(chip);
            await tester.pumpAndSettle();
            await tester.tap(chip);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$width $label');
          }
          await tester.pumpWidget(const SizedBox());
        }
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const SettingsScreen()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('حسابك'));
        await tester.pumpAndSettle();
        expect(find.text('تغيير كلمة المرور'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }, client);
  });

  setUp(() {
    savedOrders.clear();
    snapshot = null;
    failSave = false;
    ApiService.authToken = 'test';
    ApiService.currentUser = UserModel(
      id: 1,
      username: 'owner',
      fullName: 'المدير',
      role: 'owner',
      isActive: true,
      createdAt: '',
    );
    ThemeService.themeModeNotifier.value = ThemeMode.light;
  });

  Future<void> open(
    WidgetTester tester,
    double width, {
    bool dark = false,
    bool navigation = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 850);
    ThemeService.themeModeNotifier.value = dark
        ? ThemeMode.dark
        : ThemeMode.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: navigation ? const MainNavigationScreen() : const PosScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'products, tables and cart fit phone, tablet and desktop in both themes',
    (tester) async {
      await http.runWithClient(() async {
        for (final dark in [false, true]) {
          for (final width in [320.0, 390.0, 768.0, 1400.0]) {
            await open(tester, width, dark: dark);
            expect(tester.takeException(), isNull);
            await tester.tap(find.byKey(const ValueKey('add-product-1')));
            await tester.pumpAndSettle();
            if (width < 1100) {
              await tester.tap(find.byKey(const ValueKey('pos-section-2')));
              await tester.pumpAndSettle();
            }
            expect(find.byKey(const ValueKey('cart-1')), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.byKey(const ValueKey('pos-section-1')));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('table-1')), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }
        }
      }, client);
    },
  );

  testWidgets(
    'phone tabs keep quantities; saved table clears on exit and restores on reopen',
    (tester) async {
      await http.runWithClient(() async {
        await open(tester, 390);
        await tester.tap(find.byKey(const ValueKey('pos-section-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('table-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('add-product-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pos-section-2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cart-1')), findsOneWidget);
        await tester.tap(find.text('حفظ ورجوع'));
        await tester.pumpAndSettle();
        expect(savedOrders.last['items'][0]['quantity'], 1);
        await tester.tap(find.byKey(const ValueKey('pos-section-2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cart-1')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('pos-section-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('table-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pos-section-2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cart-1')), findsOneWidget);
        failSave = true;
        await tester.tap(find.text('حفظ ورجوع'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cart-1')), findsOneWidget);
        expect(find.text('حفظ ورجوع'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, client);
    },
  );

  testWidgets(
    'mobile app navigation preserves the direct-sale cart and expanded totals can scroll with keyboard',
    (tester) async {
      await http.runWithClient(() async {
        await open(tester, 390, navigation: true);
        expect(find.byType(NavigationBar), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('add-product-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('الإعدادات').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('المبيعات').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pos-section-2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cart-1')), findsOneWidget);
        final summary = find.byType(CartSummaryWidget);
        await tester.ensureVisible(summary);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.descendant(of: summary, matching: find.text('عرض التفاصيل')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: summary, matching: find.text('عرض التفاصيل')),
        );
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('مجموع صافي الربح:'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
      }, client);
    },
  );
}
