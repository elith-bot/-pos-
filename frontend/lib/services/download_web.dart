import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

void saveFile(Uint8List bytes, String filename, String mime) {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));
  final anchor = html.AnchorElement(href: url)..download = filename;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 2), () => html.Url.revokeObjectUrl(url));
}
