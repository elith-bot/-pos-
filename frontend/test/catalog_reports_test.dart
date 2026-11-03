import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/screens/main_navigation_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/widgets/product_masonry.dart';

void main() {
  testWidgets(
    'cards fill the shortest column and reflow after height changes',
    (tester) async {
      Future<void> layout(double firstHeight, int columns) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: ProductMasonry(
                columns: columns,
                children: [
                  for (var i = 0; i < 6; i++)
                    SizedBox(
                      key: ValueKey('card-$i'),
                      height: i == 0 ? firstHeight : 100,
                    ),
                ],
              ),
            ),
          ),
        );
      }

      await layout(300, 3);
      final first = tester.getRect(find.byKey(const ValueKey('card-0')));
      final short = tester.getRect(find.byKey(const ValueKey('card-1')));
      final next = tester.getRect(find.byKey(const ValueKey('card-3')));
      expect(first.left, greaterThan(short.left));
      expect(next.left, short.left);
      expect(next.top, short.bottom + 12);
      expect(next.top, lessThan(first.bottom));
      // A failed/removed image changes height without leaving a hole.
      await layout(100, 3);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('card-3'))).dx,
        first.left,
      );
      await layout(100, 1);
      for (var i = 1; i < 6; i++) {
        expect(tester.getTopLeft(find.byKey(ValueKey('card-$i'))).dy, i * 112);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'report refreshes after checkout and on return, preserving period',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ApiService.currentUser = UserModel(
        id: 1,
        username: 'manager',
        fullName: 'مدير',
        role: 'admin',
        isActive: true,
        createdAt: '',
      );
      var sales = 0;
      var reports = 0;
      var period = '';
      http.Response reply(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: MainNavigationScreen()),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'الإحصائيات'));
          await tester.pumpAndSettle();
          expect(reports, 1);
          await tester.tap(find.widgetWithText(ChoiceChip, 'كل الفترات'));
          await tester.pumpAndSettle();
          expect(period, 'all');
          await tester.tap(
            find.widgetWithText(TextButton, 'المبيعات والطاولات'),
          );
          await tester.pumpAndSettle();
          final before = reports;
          await tester.pump(const Duration(seconds: 31));
          expect(reports, before, reason: 'Hidden reports must not poll');
          await tester.tap(find.byKey(const ValueKey('add-product-1')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('checkout')));
          await tester.pumpAndSettle();
          expect(sales, 1);
          await tester.tap(find.widgetWithText(TextButton, 'الإحصائيات'));
          await tester.pumpAndSettle();
          expect(reports, before + 1);
          expect(period, 'all');
          expect(find.text('1543 د.ع'), findsWidgets);
          final activeCount = reports;
          await tester.pump(const Duration(seconds: 31));
          await tester.pumpAndSettle();
          expect(reports, activeCount + 1);
          // Expenses affect net profit and must trigger a visible report refresh.
          await ApiService.addExpense('نقل', 100, 'عام', '');
          await tester.pumpAndSettle();
          expect(reports, activeCount + 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          switch (request.url.path) {
            case '/api/products':
              return reply({
                'products': [
                  {
                    'id': 1,
                    'name': 'منتج تجريبي',
                    'selling_price': 1543,
                    'purchase_price': 1000,
                    'stock_quantity': 10,
                  },
                ],
              });
            case '/api/tables':
              return reply({'tables': []});
            case '/api/sales':
              sales++;
              return reply({'status': 'success'}, 201);
            case '/api/expenses':
              return reply({'status': 'success'}, 201);
            case '/api/stats':
              reports++;
              period = request.url.queryParameters['period']!;
              return reply({
                'stats': {
                  'total_sales_count': sales,
                  'total_revenue': sales * 1543,
                },
                'sales': [],
                'top_products': [],
                'payment_methods': {},
                'timeline': [],
              });
            default:
              return reply({});
          }
        }),
      );
    },
  );
}
