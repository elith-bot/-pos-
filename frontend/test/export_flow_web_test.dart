@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/models/user_model.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/screens/exports_screen.dart';

@JS('eval')
external JSAny? evaluate(JSString source);

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
    evaluate(
      '''
      globalThis.exportCalls = [];
      globalThis.posExportStorage = {
        prepare: async function(scope) { exportCalls.push('prepare'); return 'POS Exports/' + scope; },
        save: async function(scope, bytes, name, mime) {
          exportCalls.push(bytes);
          return JSON.stringify({filename:name, folder:'POS Exports/'+scope, size:3, modified:123, mime:mime});
        },
        list: async function() { return JSON.stringify([{filename:'pos-report-123.pdf', folder:'POS Exports/test', size:3, modified:123}]); },
        open: async function() { exportCalls.push('open'); }
      };
    '''
          .toJS,
    );
  });
  tearDown(
    () => evaluate(
      'delete globalThis.posExportStorage; delete globalThis.exportCalls;'.toJS,
    ),
  );

  test(
    'destination is prepared before export and response bytes reach storage',
    () async {
      await http.runWithClient(
        () async {
          final result = await ApiService.exportFile(
            '/api/reports/export',
            'pdf',
            query: {'period': 'all'},
          );
          expect(result['filename'], startsWith('pos-report-'));
          expect(
            (evaluate('JSON.stringify(exportCalls)'.toJS) as JSString).toDart,
            '["prepare","AP+A"]',
          );
        },
        () => MockClient((r) async {
          expect(
            (evaluate('JSON.stringify(exportCalls)'.toJS) as JSString).toDart,
            '["prepare"]',
          );
          expect(r.url.queryParameters, {'period': 'all', 'format': 'pdf'});
          return http.Response.bytes(
            [0, 255, 128],
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }),
      );
    },
  );

  test('storage preparation failure never requests a report', () async {
    evaluate(
      "posExportStorage.prepare = async () => {throw Error('cancelled');};"
          .toJS,
    );
    var requests = 0;
    await http.runWithClient(
      () async {
        await expectLater(
          ApiService.exportFile('/api/reports/export', 'pdf'),
          throwsA(anything),
        );
      },
      () => MockClient((r) async {
        requests++;
        return http.Response('', 200);
      }),
    );
    expect(requests, 0);
  });

  test('denied server export is not stored locally', () async {
    await http.runWithClient(
      () async {
        await expectLater(
          ApiService.exportFile('/api/reports/export', 'pdf'),
          throwsException,
        );
        expect(
          (evaluate('JSON.stringify(exportCalls)'.toJS) as JSString).toDart,
          '["prepare"]',
        );
      },
      () => MockClient(
        (r) async => http.Response(jsonEncode({'message': 'forbidden'}), 403),
      ),
    );
  });

  testWidgets('saved file is highlighted and local files page fits a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ExportsScreen(selectedName: 'pos-report-123.pdf'),
        ),
      );
      // Browser Promise callbacks require the real event loop, not fake time.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('آخر ملف تم تصديره'), findsOneWidget);
    expect(find.text('pos-report-123.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('اختيار مجلد آخر'), findsNothing);
    expect(find.text('معاينة الملف'), findsNothing);
  });
}
