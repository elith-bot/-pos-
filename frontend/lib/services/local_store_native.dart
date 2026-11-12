import 'dart:convert';
import 'dart:io';
class LocalStore {
  late final File file = File('${Platform.environment['LOCALAPPDATA'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path}/POS Cashier/preferences.json');
  Map<String,dynamic>? _values;
  Map<String,dynamic> get values {
    if (_values == null) {
      try { _values = Map<String,dynamic>.from(jsonDecode(file.readAsStringSync())); } catch (_) { _values = {}; }
    }
    return _values!;
  }
  String? operator [](String key) => values[key] as String?;
  void operator []=(String key, String value) { values[key] = value; save(); }
  void remove(String key) { values.remove(key); save(); }
  void save() { file.parent.createSync(recursive:true); file.writeAsStringSync(jsonEncode(values),flush:true); }
}
final store = LocalStore();
String get localServer => 'http://127.0.0.1:5000';
