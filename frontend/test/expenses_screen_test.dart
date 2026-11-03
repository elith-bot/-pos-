import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/core/app_theme.dart';
import 'package:starter_app/models/expense_model.dart';
import 'package:starter_app/screens/expenses_screen.dart';
import 'package:starter_app/services/theme_service.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/models/user_model.dart';

Map<String, dynamic> expense(
  int id,
  String title,
  double amount,
  String category,
) => {
  'id': id,
  'title': title,
  'amount': amount,
  'category': category,
  'created_by': 'موظف تجريبي',
  'created_at': '2026-10-28 20:59:59',
  'notes': 'ملاحظة خاصة بالمصروف',
};
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> showScreen(
  WidgetTester tester, {
  double width = 1400,
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1100);
  ThemeService.themeModeNotifier.value = dark
      ? ThemeMode.dark
      : ThemeMode.light;
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: const ExpensesScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ApiService.currentUser = UserModel(
      id: 1,
      username: 'admin',
      fullName: 'مدير',
      role: 'admin',
      isActive: true,
      createdAt: '',
    );
  });
  test('amount input accepts Arabic digits and rejects malformed amounts', () {
    expect(parseExpenseAmount('٢٥٬٠٠٠٫٥٠'), 25000.5);
    expect(parseExpenseAmount('۲۵۰۰۰'), 25000);
    expect(parseExpenseAmount(' 25,000.50 '), 25000.5);
    for (final input in ['0', '-5', 'NaN', 'Infinity', '1,5', '1.999', '']) {
      expect(parseExpenseAmount(input), isNull, reason: input);
    }
    expect(expenseMoney(25000.5), '25,000.50 د.ع');
  });
  test(
    'UTC timestamps and date bounds preserve final day and combine filters',
    () {
      final item = ExpenseModel.fromJson(
        expense(1, 'فاتورة الكهرباء', 1250, 'كهرباء'),
      );
      expect(item.createdAt!.toUtc(), DateTime.utc(2026, 10, 28, 20, 59, 59));
      final start = item.createdAt!;
      expect(
        item.matches(
          query: 'الكهرباء',
          category: 'كهرباء',
          start: start,
          endExclusive: start.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(item.matches(endExclusive: start), isFalse);
      expect(item.matches(category: 'رواتب'), isFalse);
      expect(item.matches(query: 'ملاحظة خاصة'), isTrue);
    },
  );

  testWidgets(
    'responsive layouts, pagination, details and search stay usable',
    (tester) async {
      final data = List.generate(
        25,
        (i) => expense(i + 1, 'مصروف رقم ${i + 1}', 100, 'عام'),
      );
      await http.runWithClient(() async {
        for (final width in [390.0, 1100.0, 1600.0]) {
          await showScreen(tester, width: width, dark: width == 1100);
          expect(tester.takeException(), isNull, reason: 'width $width');
          await tester.pumpWidget(const SizedBox());
        }
        await showScreen(tester, width: 1600);
        await tester.scrollUntilVisible(
          find.byTooltip('الصفحة التالية'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byTooltip('الصفحة التالية'));
        await tester.pumpAndSettle();
        expect(find.text('عرض 21–25 من 25'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('مصروف رقم 1'),
          -400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('مصروف رقم 1'));
        await tester.pumpAndSettle();
        expect(find.text('ملاحظة خاصة بالمصروف'), findsOneWidget);
        await tester.tap(find.text('إغلاق'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(TextField).first,
          -500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(find.byType(TextField).first, 'غير موجود');
        await tester.pumpAndSettle();
        expect(find.text('لا توجد مصاريف تطابق البحث'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => MockClient((request) async => response({'expenses': data})));
    },
  );

  testWidgets('loading failure is not shown as an empty ledger', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await showScreen(tester);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.text('ابدأ بتسجيل أول مصروف'), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async => response({}, 500)));
  });

  testWidgets(
    'form validates, retains failed save, and closes only on success',
    (tester) async {
      var writes = 0;
      var accept = false;
      await http.runWithClient(
        () async {
          await showScreen(tester);
          await tester.tap(find.text('تسجيل مصروف'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('حفظ المصروف'));
          await tester.pumpAndSettle();
          expect(find.text('أدخل عنوان المصروف'), findsOneWidget);
          expect(writes, 0);
          await tester.enterText(
            find.byType(TextFormField).at(0),
            'فاتورة تجريبية',
          );
          await tester.enterText(find.byType(TextFormField).at(1), '٢٥٬٠٠٠');
          await tester.tap(find.text('حفظ المصروف'));
          await tester.pumpAndSettle();
          expect(writes, 1);
          expect(
            find.text('لم يتم تأكيد الحفظ. تحقق من الاتصال ثم أعد المحاولة.'),
            findsOneWidget,
          );
          expect(find.text('فاتورة تجريبية'), findsOneWidget);
          accept = true;
          await tester.tap(find.text('حفظ المصروف'));
          await tester.pumpAndSettle();
          expect(writes, 2);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            expect(jsonDecode(request.body)['amount'], 25000);
            return response({}, accept ? 201 : 500);
          }
          return response({'expenses': []});
        }),
      );
    },
  );

  testWidgets('delete requires confirmation and failure keeps the record', (
    tester,
  ) async {
    var deletes = 0;
    var accept = false;
    await http.runWithClient(
      () async {
        await showScreen(tester);
        await tester.ensureVisible(find.byTooltip('حذف المصروف'));
        await tester.tap(find.byTooltip('حذف المصروف'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(deletes, 0);
        await tester.tap(find.byTooltip('حذف المصروف'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'حذف المصروف'));
        await tester.pumpAndSettle();
        expect(deletes, 1);
        expect(find.text('فاتورة الكهرباء'), findsOneWidget);
        accept = true;
        await tester.tap(find.byTooltip('حذف المصروف'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'حذف المصروف'));
        await tester.pumpAndSettle();
        expect(deletes, 2);
        expect(find.text('فاتورة الكهرباء'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          return response({}, accept ? 200 : 500);
        }
        return response({
          'expenses': [expense(1, 'فاتورة الكهرباء', 100, 'كهرباء')],
        });
      }),
    );
  });
}
