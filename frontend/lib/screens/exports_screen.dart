import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

Future<void> showSavedExport(
  BuildContext context,
  Map<String, dynamic> file,
) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'افتح قائمة التنزيلات في المتصفح، ثم اختر إظهار الملف في المجلد.',
        ),
      ),
    );
    return;
  }
  if (!kIsWeb) {
    try {
      await ApiService.openLocalExport(file);
      return;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
  if (context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportsScreen(selectedName: file['filename']),
      ),
    );
  }
}

class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key, this.selectedName});
  final String? selectedName;
  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  List<Map<String, dynamic>> files = [];
  String? error, folder;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool prepare = true, bool change = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final path = prepare
          ? await ApiService.prepareExportFolder(change: change)
          : folder;
      final result = await ApiService.localExports();
      if (!mounted) return;
      setState(() {
        files = result;
        folder = path ?? (files.isEmpty ? null : files.first['folder']);
        if (widget.selectedName != null) {
          files.sort(
            (a, b) => a['filename'] == b['filename']
                ? 0
                : a['filename'] == widget.selectedName
                ? -1
                : b['filename'] == widget.selectedName
                ? 1
                : (b['modified'] as num).compareTo(a['modified'] as num),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(Map<String, dynamic> file) async {
    try {
      await ApiService.openLocalExport(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('ملفات الكاشير المحلية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            kIsWeb
                ? 'سجل التصدير خلال هذه الجلسة. تجد الملفات في تنزيلات المتصفح؛ السجل لا يؤكد اكتمال التنزيل.'
                : 'تُحفظ التصديرات تلقائياً في POS Exports. يظهر مكان الحفظ أدناه.',
          ),
          if (kIsWeb)
            const Text(
              'لفتح ملف، استخدم قائمة التنزيلات في المتصفح ثم إظهار الملف في المجلد. مكان التنزيل يتبع إعدادات متصفحك.',
            ),
          if (folder != null) SelectableText('المجلد: $folder'),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: loading ? null : () => load(),
                icon: const Icon(Icons.folder_open),
                label: const Text('تحديث القائمة'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!loading && error == null && files.isEmpty)
            Text(
              kIsWeb
                  ? 'لا توجد تصديرات في هذه الجلسة.'
                  : 'لا توجد تصديرات محفوظة لهذا الحساب في المجلد.',
            ),
          for (final file in files)
            Card(
              color: file['filename'] == widget.selectedName
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (file['filename'] == widget.selectedName)
                      const Text(
                        'آخر ملف تم تصديره',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    SelectableText('${file['filename']}'),
                    Text(
                      '${DateTime.fromMillisecondsSinceEpoch((file['modified'] as num).toInt())} • ${((file['size'] as num) / 1024).toStringAsFixed(1)} KB',
                    ),
                    if (!kIsWeb)
                      TextButton.icon(
                        onPressed: () => open(file),
                        icon: Icon(
                          kIsWeb
                              ? Icons.visibility_outlined
                              : Icons.folder_open,
                        ),
                        label: Text(kIsWeb ? 'معاينة الملف' : 'عرض الملف'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
