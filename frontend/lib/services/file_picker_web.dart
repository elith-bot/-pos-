import 'dart:async';
import 'dart:convert';
// Conditional import for Flutter web vs desktop/mobile
import 'dart:html' as html;

class FilePickerHelper {
  static Future<String?> pickImageAsBase64() async {
    final Completer<String?> completer = Completer<String?>();

    try {
      final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
      uploadInput.accept = 'image/*';
      uploadInput.click();

      uploadInput.onChange.listen((e) {
        final files = uploadInput.files;
        if (files != null && files.isNotEmpty) {
          final file = files[0];
          final reader = html.FileReader();

          reader.onLoadEnd.listen((e) {
            final result = reader.result;
            if (result is String) {
              completer.complete(result);
            } else {
              completer.complete(null);
            }
          });

          reader.onError.listen((e) {
            completer.complete(null);
          });

          reader.readAsDataUrl(file);
        } else {
          completer.complete(null);
        }
      });
    } catch (e) {
      print('File picker error: $e');
      completer.complete(null);
    }

    return completer.future;
  }
}
