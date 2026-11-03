import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
      await ApiService.exportFile(
        widget.path,
        format,
        query: widget.query,
        body: widget.body,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تجهيز الملف وتنزيله.')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => busy
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
            PopupMenuItem(value: 'xlsx', child: Text('Excel • جداول')),
            PopupMenuItem(value: 'csv', child: Text('CSV • بيانات جدولية')),
            PopupMenuItem(value: 'json', child: Text('JSON • بيانات كاملة')),
          ],
        );
}
