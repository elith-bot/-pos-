import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:starter_app/services/download_stub.dart' as storage;

class DocumentsDirectory extends PathProviderPlatform {
  DocumentsDirectory(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local exports preserve bytes, isolate accounts, and reject traversal',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'pos-export-test-',
      );
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = DocumentsDirectory(temporary.path);
      storage.exportBaseDirectoryOverride = temporary.path;
      try {
        final folder = await storage.prepareFolder('user-1-owner');
        expect(folder, contains('POS Exports'));
        final bytes = Uint8List.fromList([0, 255, 1, 128, 10]);
        final file = await storage.saveFile(
          'user-1-owner',
          bytes,
          'pos-report-123.pdf',
          'application/pdf',
        );
        expect(await File('$folder/${file['filename']}').readAsBytes(), bytes);
        expect((await storage.listFiles('user-1-owner')).single['size'], 5);
        expect(await storage.listFiles('user-2-cashier'), isEmpty);
        await File(
          '$folder/pos-report-456.pdf.part',
        ).writeAsString('incomplete');
        expect(await storage.listFiles('user-1-owner'), hasLength(1));
        await expectLater(
          storage.prepareFolder('../outside'),
          throwsArgumentError,
        );
        await expectLater(
          storage.saveFile(
            'user-1-owner',
            bytes,
            '../outside.pdf',
            'application/pdf',
          ),
          throwsArgumentError,
        );
        await expectLater(
          storage.openFile('user-1-owner', 'pos-missing.pdf'),
          throwsException,
        );
      } finally {
        PathProviderPlatform.instance = original;
        storage.exportBaseDirectoryOverride = null;
        await temporary.delete(recursive: true);
      }
    },
  );
}
