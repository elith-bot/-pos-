import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starter_app/services/api_service.dart';

void main() {
  test(
    'session validation times out while server never sends headers',
    () async {
      ApiService.authToken = 'test-only';
      try {
        final result = await http.runWithClient(
          () =>
              ApiService.validateSession().timeout(const Duration(seconds: 23)),
          () => MockClient((_) => Completer<http.Response>().future),
        );
        expect(result, isNull);
      } finally {
        ApiService.authToken = null;
      }
    },
  );
}
