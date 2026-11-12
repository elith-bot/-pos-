import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/foundation.dart';

final _validName = RegExp(r'^pos-[a-z0-9-]+\.(pdf|xlsx|csv|json)$');
@visibleForTesting
String? exportBaseDirectoryOverride;

// Desktop exports belong beside the installed executable. Mobile apps use
// their documents directory because the application bundle is not writable.
Future<Directory> exportDirectoryIn(String parent, String scope) async {
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(scope)) {
    throw ArgumentError('Invalid export scope');
  }
  final folder = await Directory(
    '$parent/POS Exports/$scope',
  ).create(recursive: true);
  final probe = await folder.createTemp('.write-check-');
  await probe.delete();
  return folder;
}

Future<Directory> _folder(String scope) async {
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(scope)) {
    throw ArgumentError('Invalid export scope');
  }
  if (exportBaseDirectoryOverride != null) {
    return exportDirectoryIn(exportBaseDirectoryOverride!, scope);
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      return await exportDirectoryIn(
        File(Platform.resolvedExecutable).parent.path,
        scope,
      );
    } on FileSystemException {
      // Installed application folders may be read-only.
    }
  }
  final documents = await getApplicationDocumentsDirectory();
  return exportDirectoryIn(documents.path, scope);
}

Future<String> prepareFolder(String scope, {bool change = false}) async =>
    (await _folder(scope)).path;

Future<Map<String, dynamic>> saveFile(
  String scope,
  Uint8List bytes,
  String filename,
  String mime,
) async {
  if (!_validName.hasMatch(filename)) throw ArgumentError('Invalid filename');
  final folder = await _folder(scope);
  final file = File('${folder.path}/$filename');
  final pending = File('${file.path}.part');
  try {
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(file.path);
  } catch (_) {
    if (await pending.exists()) await pending.delete();
    rethrow;
  }
  return {
    'filename': filename,
    'folder': folder.path,
    'size': bytes.length,
    'modified': (await file.lastModified()).millisecondsSinceEpoch,
    'mime': mime,
  };
}

Future<List<Map<String, dynamic>>> listFiles(String scope) async {
  final folder = await _folder(scope);
  final files = <Map<String, dynamic>>[];
  await for (final entry in folder.list(followLinks: false)) {
    final name = entry.uri.pathSegments.last;
    if (entry is! File || !_validName.hasMatch(name)) continue;
    final stat = await entry.stat();
    files.add({
      'filename': name,
      'folder': folder.path,
      'size': stat.size,
      'modified': stat.modified.millisecondsSinceEpoch,
    });
  }
  files.sort((a, b) => (b['modified'] as int).compareTo(a['modified'] as int));
  return files;
}

Future<void> openFile(String scope, String filename) async {
  if (!_validName.hasMatch(filename)) throw ArgumentError('Invalid filename');
  final file = File('${(await _folder(scope)).path}/$filename');
  if (!await file.exists()) throw Exception('الملف نُقل أو حُذف من المجلد.');
  if (Platform.isWindows) {
    await Process.start('explorer.exe', [
      '/select,',
      file.absolute.path.replaceAll('/', '\\'),
    ]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', file.path]);
  } else {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) throw Exception(result.message);
  }
}
