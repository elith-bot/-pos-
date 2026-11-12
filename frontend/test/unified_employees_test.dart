import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/screens/employees_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/widgets/report_datetime_picker.dart';

void main() {
  testWidgets(
    'legacy accounts and automatic phone login share one employee page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ApiService.currentUser = UserModel(
        id: 1,
        username: 'owner',
        fullName: 'مالك',
        role: 'owner',
        isActive: true,
        createdAt: '',
      );
      Map<String, dynamic>? saved;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: EmployeesScreen())),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('موظف قديم'), findsOneWidget);
          expect(find.text('إكمال ملف الموظف والعقد'), findsOneWidget);
          expect(find.text('حسابات الدخول والصلاحيات'), findsNothing);
          await tester.tap(find.text('إضافة موظف وعقد'));
          await tester.pumpAndSettle();
          for (final pair in {
            'الاسم الكامل': 'موظف جديد',
            'رقم الهاتف (اسم الدخول للحساب الجديد)': '07701234567',
            'كلمة مرور الحساب': 'employee123',
          }.entries) {
            final field = find.widgetWithText(TextFormField, pair.key);
            await tester.ensureVisible(field);
            await tester.enterText(field, pair.value);
          }
          final role = tester.widget<DropdownButtonFormField<String>>(
            find.widgetWithText(
              DropdownButtonFormField<String>,
              'الدور والصلاحيات',
            ),
          );
          expect(role.initialValue, 'cashier');
          await tester.tap(find.text('حفظ'));
          await tester.pumpAndSettle();
          expect(saved?['phone'], '07701234567');
          expect(saved?['account'], {
            'role': 'cashier',
            'password': 'employee123',
          });
          expect(saved?['contract'], isNotNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((r) async {
          if (r.method == 'POST') saved = jsonDecode(r.body);
          return http.Response(
            jsonEncode({
              'staff': [],
              'attendance': [],
              'payroll': [],
              'unlinked_users': [
                {
                  'id': 2,
                  'username': 'old',
                  'full_name': 'موظف قديم',
                  'role': 'cashier',
                  'is_active': true,
                  'created_at': '2026-01-01',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    },
  );

  testWidgets('date and time can be selected together on phone and desktop', (
    tester,
  ) async {
    for (final width in [390.0, 1400.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await pickReportDateTime(
                    ctx,
                    initial: DateTime(2026, 10, 31, 9, 15),
                    title: 'التاريخ والوقت',
                  );
                },
                child: const Text('اختيار'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('اختيار'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('report-hour')));
      await tester.tap(find.byKey(const ValueKey('report-hour')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-report-datetime')));
      await tester.pumpAndSettle();
      expect(result, DateTime(2026, 10, 31, 10, 15));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
