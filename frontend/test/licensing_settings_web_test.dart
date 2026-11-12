import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/screens/activation_screen.dart';
import 'package:starter_app/screens/settings_screen.dart';
import 'package:starter_app/services/api_service.dart';
import 'package:starter_app/services/system_settings_service.dart';
import 'package:starter_app/models/user_model.dart';

void main() {
  testWidgets('invalid activation stays locked, valid token opens login', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiService.onLicenseRequired = null;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ActivationScreen()));
      await tester.pumpAndSettle();
      expect(find.text('POSREQ1-test-device'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.text('تفعيل النسخة'));
      await tester.pumpAndSettle();
      expect(find.textContaining('رمز غير صحيح'), findsOneWidget);
      expect(find.byType(ActivationScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'valid-test-token');
      await tester.tap(find.text('تفعيل النسخة'));
      await tester.pumpAndSettle();
      expect(find.byType(ActivationScreen), findsNothing);
      expect(find.text('تسجيل الدخول للنظام'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.method == 'POST') {
        return jsonDecode(request.body)['token'] == 'valid-test-token'
          ? http.Response('{"active":true}',200)
          : http.Response(jsonEncode({'message':'رمز غير صحيح'}),400);
      }
      return http.Response(jsonEncode({'active':false,'required':true,'request_code':'POSREQ1-test-device','message':'تحتاج إلى التفعيل'}),200);
    }));
  });

  testWidgets('settings save tab visibility with revision and remove connection fields', (tester) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ApiService.currentUser = UserModel(id:1,username:'owner',fullName:'مالك',role:'owner',isActive:true,createdAt:'');
    Map<String,dynamic>? saved;
    final settings = {'business_name':'متجر اختبار','business_phone':'','business_address':'','business_type':'general','session_hours':12,
      'tabs':{'sales':true,'tables':true,'expenses':true,'analytics':true,'employees':true}};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('اتصال السيرفر'),findsNothing);
      expect(find.text('قاعدة البيانات'),findsNothing);
      final tables = find.widgetWithText(SwitchListTile,'الطاولات');
      await tester.ensureVisible(tables);
      await tester.tap(tables);
      await tester.pumpAndSettle();
      final save = find.text('حفظ إعدادات النظام');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved?['revision'],3);
      expect(saved?['settings']['tabs']['tables'],false);
      expect(SystemSettingsService.visible('tables'),false);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.method == 'PUT') {
        saved = jsonDecode(request.body);
        return http.Response(jsonEncode({'settings':saved!['settings'],'revision':4}),200);
      }
      return http.Response(jsonEncode({'settings':settings,'revision':3,'presets':{'general':'عام'},
        'tabs':{'sales':'المبيعات','tables':'الطاولات','expenses':'المصاريف','analytics':'الإحصائيات','employees':'الموظفون'}}),200);
    }));
    ApiService.currentUser = null;
    SystemSettingsService.values = {};
  });
}
