import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/screens/pos_screen.dart';
import 'package:starter_app/screens/analytics_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/widgets/export_menu.dart';

void main() {
  setUp(
    () => ApiService.currentUser = UserModel(
      id: 1,
      username: 'owner',
      fullName: 'مالك',
      role: 'owner',
      isActive: true,
      createdAt: '',
    ),
  );
  http.Response reply(Object data) => http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  testWidgets(
    'weighted product keeps editable initial stock when mode changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: PosScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('إضافة منتج'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('يباع بالوزن؟'));
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        final stock = find.widgetWithText(
          TextField,
          'الوزن الأولي بالمخزن (غم)',
        );
        expect(stock, findsOneWidget);
        await tester.ensureVisible(stock);
        await tester.enterText(stock, '1500');
        expect(tester.widget<TextField>(stock).controller!.text, '1500');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((r) async => reply({'products': [], 'tables': []})));
    },
  );

  testWidgets(
    'hour presets and custom hours use server filter and freeze export bounds',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, String> query = {};
      const frozen = {
        'period': 'custom_time',
        'start_at': '2026-11-01T08:00:00Z',
        'end_at': '2026-11-01T12:00:00Z',
        'tz_offset': '180',
      };
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: AnalyticsScreen())),
          );
          await tester.pumpAndSettle();
          for (final h in [1, 4, 6, 8, 12, 16]) {
            await tester.tap(find.widgetWithText(ChoiceChip, 'آخر $h ساعة'));
            await tester.pumpAndSettle();
            expect(query['period'], 'hours');
            expect(double.parse(query['hours']!), h.toDouble());
          }
          final hours = find.byType(TextFormField);
          await tester.enterText(hours, '2.5');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(query['hours'], '2.5');
          expect(
            tester.widget<ExportMenu>(find.byType(ExportMenu)).query,
            frozen,
          );
          await tester.tap(find.widgetWithText(ChoiceChip, 'مخصصة'));
          await tester.pumpAndSettle();
          expect(query['period'], 'custom_time');
          expect(
            DateTime.parse(
              query['start_at']!,
            ).isBefore(DateTime.parse(query['end_at']!)),
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((r) async {
          query = r.url.queryParameters;
          return reply({
            'stats': {},
            'sales': [],
            'top_products': [],
            'payment_methods': {},
            'timeline': [],
            'resolved_filter': frozen,
          });
        }),
      );
    },
  );
}
