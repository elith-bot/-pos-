import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/core/app_theme.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/models/product_model.dart';
import 'package:starter_app/models/cart_item_model.dart';
import 'package:starter_app/screens/pos_screen.dart';
import 'package:starter_app/screens/analytics_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/services/theme_service.dart';
import 'package:starter_app/widgets/sale_details_dialog.dart';

const receipt = {
  'id': 7,
  'cashier_name': 'موظف تجريبي',
  'created_at': '2026-10-31 12:30:00',
  'payment_method': 'نقداً',
  'order_type': 'table',
  'table_name': 'طاولة 1',
  'total_selling_amount': 5000,
  'total_discount': 1000,
  'total_purchase_cost': 3000,
  'net_profit': 1000,
  'items': [
    {
      'product_id': 1,
      'product_name': 'قهوة',
      'quantity': 500,
      'is_weight': true,
      'weight_unit_grams': 1000,
      'unit_selling_price': 10000,
      'unit_purchase_price': 6000,
      'discount': 2000,
      'discount_amount': 1000,
      'gross_amount': 5000,
      'total_price': 4000,
      'profit': 1000,
      'total_purchase_cost': 3000,
    },
  ],
};

void main() {
  void user(String role) {
    ApiService.currentUser = UserModel(
      id: 1,
      username: role,
      fullName: role,
      role: role,
      isActive: true,
      createdAt: '',
    );
    ThemeService.themeModeNotifier.value = ThemeMode.light;
  }

  Future<void> showReceipt(
    WidgetTester tester,
    String role,
    double width, {
    Map<String, dynamic> data = receipt,
  }) async {
    user(role);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SaleDetailsDialog(sale: data, periodRevenue: 20000),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('receipt-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('expanded cart item hides purchase and profit from cashier', (
    tester,
  ) async {
    for (final role in ['cashier', 'admin', 'owner', 'developer']) {
      user(role);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      final product = ProductModel.fromJson({
        'id': 1,
        'name': 'قهوة',
        'purchase_price': 1000,
        'selling_price': 1500,
        'stock_quantity': 100,
      });
      final item = CartItemModel(
        product: product,
        quantity: 1,
        unitPurchasePrice: 1000,
        unitSellingPrice: 1500,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CartItemWidget(
                item: item,
                onUpdate: () {},
                onUpdateQuantity: (_, quantity) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('عرض التفاصيل'));
      await tester.pumpAndSettle();
      expect(
        find.text('شراء: 1000 د.ع'),
        role == 'cashier' ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('كلفة الشراء: 1000 د.ع'),
        role == 'cashier' ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('الربح: 500 د.ع'),
        role == 'cashier' ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'receipt totals and weighted item statistics respect every role',
    (tester) async {
      for (final role in ['cashier', 'admin', 'owner', 'developer']) {
        for (final width in [320.0, 1200.0]) {
          await showReceipt(tester, role, width);
          expect(find.text('4000 د.ع'), findsWidgets);
          await reveal(tester, 'صافي الإيراد / النهائي');
          expect(
            find.text('إجمالي تكلفة الشراء'),
            role == 'cashier' ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('ربح الطلب'),
            role == 'cashier' ? findsNothing : findsOneWidget,
          );
          await reveal(tester, 'مساهمة الصنف في الطلب');
          expect(find.text('صافي سعر وحدة التسعير / 1000 غم'), findsOneWidget);
          expect(find.text('8000 د.ع'), findsOneWidget);
          expect(
            find.text('تكلفة شراء الصنف'),
            role == 'cashier' ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('ربح الصنف'),
            role == 'cashier' ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
  testWidgets(
    'old receipts do not invent weight units and cashier cannot fetch analytics',
    (tester) async {
      final old = Map<String, dynamic>.from(receipt);
      old['items'] = [
        {
          'product_id': 1,
          'product_name': 'قديم',
          'quantity': 500,
          'unit_selling_price': 10000,
          'unit_purchase_price': 6000,
          'discount': 2000,
          'total_price': 4000,
          'profit': 1000,
        },
      ];
      await showReceipt(tester, 'admin', 390, data: old);
      await reveal(tester, 'مساهمة الصنف في الطلب');
      expect(find.textContaining('/ 1000 غم'), findsNothing);
      expect(find.text('غير مسجل'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      user('cashier');
      var requests = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: AnalyticsScreen()));
          await tester.pumpAndSettle();
          expect(find.text('هذه الصفحة متاحة للإدارة فقط.'), findsOneWidget);
          expect(requests, 0);
        },
        () => MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
    },
  );
  testWidgets(
    'photo fills card width, missing photo has no placeholder, summary stays pinned',
    (tester) async {
      user('owner');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      final products = List.generate(
        8,
        (i) => {
          'id': i + 1,
          'name': 'منتج ${i + 1}',
          'selling_price': 1500,
          'purchase_price': 1000,
          'stock_quantity': 100,
          if (i == 0)
            'image_url':
                'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh4sAAAAASUVORK5CYII=',
        },
      );
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.lightTheme, home: const PosScreen()),
          );
          await tester.pumpAndSettle();
          final photo = find.descendant(
            of: find.byKey(const ValueKey('product-1')),
            matching: find.byType(Image),
          );
          expect(photo, findsOneWidget);
          expect(tester.getSize(photo).height, greaterThan(200));
          expect(
            tester.getSize(find.byKey(const ValueKey('product-1'))).height,
            closeTo(
              tester.getSize(find.byKey(const ValueKey('product-2'))).height *
                      2 +
                  12,
              1,
            ),
          );
          expect(tester.getSize(photo).width, greaterThan(200));
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('product-2')),
              matching: find.byType(Image),
            ),
            findsNothing,
          );
          for (var i = 1; i <= 6; i++) {
            final button = find.byKey(ValueKey('add-product-$i'));
            await tester.scrollUntilVisible(
              button,
              220,
              scrollable: find
                  .descendant(
                    of: find.byKey(const PageStorageKey('pos-products')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            await tester.tap(button);
            await tester.pumpAndSettle();
          }
          final summary = find.byKey(const ValueKey('pinned-cart-summary'));
          final before = tester.getTopLeft(summary);
          await tester.drag(
            find.byKey(const PageStorageKey('pos-cart')),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(summary), before);
          expect(find.byKey(const ValueKey('checkout')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/products')
                  ? {'products': products}
                  : {'tables': []},
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    },
  );
}
