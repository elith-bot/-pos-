import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('posExportStorage')
external _ExportStorage? get _storage;

extension type _ExportStorage(JSObject _) implements JSObject {
  external JSPromise<JSString> prepare(JSString scope, JSBoolean change);
  external JSPromise<JSString> save(
    JSString scope,
    JSString bytes,
    JSString filename,
    JSString mime,
  );
  external JSPromise<JSString> list(JSString scope);
  external JSPromise<JSAny?> open(JSString scope, JSString filename);
}

_ExportStorage get _ready {
  final storage = _storage;
  if (storage == null) {
    throw Exception('حدّث صفحة المتصفح لتحميل أدوات الحفظ المحلي.');
  }
  return storage;
}

Future<String> prepareFolder(String scope, {bool change = false}) async =>
    (await _ready.prepare(scope.toJS, change.toJS).toDart).toDart;

Future<Map<String, dynamic>> saveFile(
  String scope,
  Uint8List bytes,
  String filename,
  String mime,
) async => Map<String, dynamic>.from(
  jsonDecode(
    (await _ready
            .save(
              scope.toJS,
              base64Encode(bytes).toJS,
              filename.toJS,
              mime.toJS,
            )
            .toDart)
        .toDart,
  ),
);

Future<List<Map<String, dynamic>>> listFiles(String scope) async =>
    List<Map<String, dynamic>>.from(
      jsonDecode((await _ready.list(scope.toJS).toDart).toDart),
    );

Future<void> openFile(String scope, String filename) async {
  await _ready.open(scope.toJS, filename.toJS).toDart;
}
