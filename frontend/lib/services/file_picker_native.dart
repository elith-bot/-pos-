import 'dart:convert';
import 'package:file_selector/file_selector.dart';
class FilePickerHelper {
  static Future<String?> pickImageAsBase64() async {
    final file = await openFile(acceptedTypeGroups: [const XTypeGroup(label:'Images',extensions:['png','jpg','jpeg','webp','gif'])]);
    if (file == null) return null;
    final extension = file.name.split('.').last.toLowerCase();
    final mime = extension == 'jpg' ? 'jpeg' : extension;
    return 'data:image/$mime;base64,${base64Encode(await file.readAsBytes())}';
  }
}
