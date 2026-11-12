import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}
class _SupportScreenState extends State<SupportScreen> {
  bool busy = false;
  String? message;
  List<dynamic> logs = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final status = await ApiService.businessRequest('/api/support/status');
      if (mounted) setState(() => logs = status['logs'] as List? ?? []);
    } catch (e) { if (mounted) setState(() => message = '$e'); }
  }
  Future<void> diagnose() async {
    final consent = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('فحص محلي مع نسخة احتياطية'),
      content: const Text('سيُنشئ النظام نسخة احتياطية محلية ويفحص سلامتها. لا تُرسل بيانات خارج جهازك ولا تتغير الفواتير.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('موافق، ابدأ الفحص'))]));
    if (consent != true || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await ApiService.businessRequest('/api/support/repair-db', method: 'POST', body: {'consent': true});
      final data = result['results'] as Map;
      if (mounted) setState(() => message = 'النسخة الاحتياطية: ${data['backup']}\nسلامة البيانات: ${data['integrity']}\nملاحظات العلاقات: ${data['foreign_key_issues']}');
      await load();
    } catch (e) { if (mounted) setState(() => message = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Text('الدعم والصيانة')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('الدعم عن بُعد غير موصول حالياً', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Text('لا توجد مشاركة شاشة أو تحكم عن بُعد. سيُتاح الاتصال بعد تجهيز خادم الدعم، وبموافقتك لكل جلسة.'),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: busy ? null : diagnose, icon: const Icon(Icons.health_and_safety_outlined), label: const Text('نسخة احتياطية وفحص محلي')),
      if (busy) const LinearProgressIndicator(),
      if (message != null) SelectableText(message!),
      const SizedBox(height: 24),
      const Text('سجل الصيانة المحلية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      for (final log in logs) ListTile(title: Text('${log['details']}'), subtitle: Text('${log['timestamp']} • ${log['user']}')),
    ]),
  ));
}
