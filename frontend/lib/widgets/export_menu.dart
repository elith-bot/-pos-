import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';
import '../screens/exports_screen.dart';

class ExportMenu extends StatefulWidget {
  const ExportMenu({
    super.key,
    required this.path,
    this.query,
    this.body,
    this.enabled = true,
    this.label = 'تصدير',
  });
  final String path, label;
  final Map<String, String>? query;
  final Map<String, dynamic>? body;
  final bool enabled;
  @override
  State<ExportMenu> createState() => _ExportMenuState();
}

class _ExportMenuState extends State<ExportMenu> {
  bool busy = false;
  Future<void> export(String format) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file = await ApiService.exportFile(
        widget.path,
        format,
        query: widget.query,
        body: widget.body,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              file['download'] == true
                  ? 'أُرسل الملف إلى تنزيلات المتصفح.'
                  : 'تم حفظ الملف في: ${file['folder']}',
            ),
            duration: const Duration(seconds: 12),
            action: SnackBarAction(
              label: file['download'] == true ? 'مكان الملف' : 'عرض الملف',
              onPressed: () => showSavedExport(context, file),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) =>
      !appPermissions.has(
        widget.path.contains('/reports')
            ? 'exports.reports'
            : widget.path.contains('/cart')
            ? 'exports.cart'
            : 'exports.orders',
      )
      ? const SizedBox.shrink()
      : busy
      ? const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : PopupMenuButton<String>(
          tooltip: widget.label,
          enabled: widget.enabled,
          onSelected: export,
          icon: const Icon(Icons.file_download_outlined),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'pdf', child: Text('PDF • مستند')),
            PopupMenuItem(
              value: 'xlsx',
              child: Text('Excel XLSX • ملف منسق من اليمين لليسار'),
            ),
            PopupMenuItem(
              value: 'csv',
              child: Text('CSV • بيانات نصية بدون تنسيق'),
            ),
            PopupMenuItem(value: 'json', child: Text('JSON • بيانات كاملة')),
          ],
        );
}
