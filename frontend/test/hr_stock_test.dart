import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/screens/pos_screen.dart';
import 'package:starter_app/screens/hr_screen.dart';
import 'package:starter_app/screens/fixed_expenses_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/core/app_theme.dart';

void main() {
  setUp(() {
    ApiService.currentUser = UserModel(
      id: 1,
      username: 'owner',
      fullName: 'مالك',
      role: 'owner',
      isActive: true,
      createdAt: '',
    );
  });
  http.Response response(Object d) => http.Response(
    jsonEncode(d),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  testWidgets('zero stock and manual excess quantities cannot enter the cart', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: const PosScreen()),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('add-product-1')))
              .onPressed,
          isNull,
        );
        final field = find.byKey(const ValueKey('quantity-1'));
        await tester.enterText(field, '5');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, '0');
        await tester.tap(find.byKey(const ValueKey('add-product-2')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('add-product-2')))
              .onPressed,
          isNull,
        );
        await tester.enterText(find.byKey(const ValueKey('quantity-2')), '9');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('quantity-2')))
              .controller!
              .text,
          '1',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient(
        (r) async => response(
          r.url.path.endsWith('/products')
              ? {
                  'products': [
                    {
                      'id': 1,
                      'name': 'نفد',
                      'selling_price': 100,
                      'purchase_price': 50,
                      'stock_quantity': 0,
                    },
                    {
                      'id': 2,
                      'name': 'آخر قطعة',
                      'selling_price': 100,
                      'purchase_price': 50,
                      'stock_quantity': 1,
                    },
                  ],
                }
              : {'tables': []},
        ),
      ),
    );
  });
  testWidgets(
    'HR forms, contract viewer and monthly expenses fit phone and desktop',
    (tester) async {
      final contract = {
        'effective_month': '2026-10',
        'pay_type': 'hourly',
        'rate': 100,
        'shift_start': '09:00',
        'shift_end': '17:00',
        'workdays': '0,1,2,3,4',
        'grace_minutes': 5,
        'late_per_minute': 0,
        'absence_per_day': 0,
        'fixed_deduction': 0,
        'bonus_type': 'none',
        'bonus_amount': 0,
        'contract_notes': 'الشروط الخاصة بي',
      };
      await http.runWithClient(
        () async {
          for (final width in [390.0, 1400.0]) {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 1000);
            await tester.pumpWidget(
              MaterialApp(theme: AppTheme.lightTheme, home: const HrScreen()),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('إضافة موظف وعقد'));
            await tester.pumpAndSettle();
            expect(find.text('نوع الراتب / الأجر'), findsOneWidget);
            expect(
              find.text('شروط العقد والإجازات وباقي الاتفاقات'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('إلغاء'));
            await tester.pumpAndSettle();
            for (final tab in ['الحضور والإجازات', 'الرواتب']) {
              await tester.tap(find.text(tab));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(
              const MaterialApp(home: FixedExpensesScreen()),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('إضافة التزام'));
            await tester.pumpAndSettle();
            expect(find.text('المبلغ الشهري'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('إلغاء'));
            await tester.pumpAndSettle();
            ApiService.currentUser = UserModel(
              id: 2,
              username: 'cash',
              fullName: 'كاشير',
              role: 'cashier',
              isActive: true,
              createdAt: '',
            );
            await tester.pumpWidget(
              const MaterialApp(home: MyContractScreen()),
            );
            await tester.pumpAndSettle();
            expect(find.text('الشروط الخاصة بي'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            ApiService.currentUser = UserModel(
              id: 1,
              username: 'owner',
              fullName: 'مالك',
              role: 'owner',
              isActive: true,
              createdAt: '',
            );
          }
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/users')) return response({'users': []});
          if (r.url.path.endsWith('/my-contract'))
            return response({
              'staff': {'name': 'موظف', 'job_title': 'كاشير'},
              'contracts': [contract],
            });
          return response({
            'staff': [],
            'attendance': [],
            'payroll': [],
            'fixed_expenses': [],
          });
        }),
      );
    },
  );
}
