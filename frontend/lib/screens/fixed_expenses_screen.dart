import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';
import '../widgets/business_form.dart';
import 'hr_screen.dart' show amount, monthLabel;

class FixedExpensesScreen extends StatefulWidget {
  const FixedExpensesScreen({super.key});
  @override
  State<FixedExpensesScreen> createState() => _FixedExpensesScreenState();
}

class _FixedExpensesScreenState extends State<FixedExpensesScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  int version = 0;
  String? error;
  final busy = <int>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!appPermissions.canManageHR) return;
    final v = ++version;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await ApiService.businessRequest(
        '/api/fixed-expenses',
        query: {'month': monthLabel(month)},
      );
      if (mounted && v == version)
        setState(() {
          rows = List<Map<String, dynamic>>.from(d['fixed_expenses']);
          loading = false;
        });
    } catch (e) {
      if (mounted && v == version)
        setState(() {
          error = '$e';
          loading = false;
        });
    }
  }

  void notice(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    final saved = await businessForm(
      context,
      title: row == null ? 'إضافة التزام شهري' : 'تعديل الالتزام',
      description:
          'جدول للاستحقاقات الشهرية. لا يُسجل مصروف إلا عند تأكيد الدفع، والتعديل يخص الدفعات القادمة فقط.',
      initial: {'amount': 0, 'due_day': 1, ...?row},
      fields: [
        const BusinessField('title', 'اسم الالتزام / الجهة'),
        const BusinessField('amount', 'المبلغ الشهري', kind: 'number'),
        if (row == null)
          const BusinessField(
            'category',
            'التصنيف',
            options: {
              'إيجار': 'إيجار',
              'اشتراكات': 'اشتراكات',
              'خدمات': 'خدمات',
              'مدفوعات ثابتة': 'مدفوعات ثابتة',
            },
          ),
        const BusinessField('due_day', 'يوم الاستحقاق (1–28)', kind: 'number'),
        if (row == null)
          const BusinessField(
            'notes',
            'ملاحظات',
            kind: 'notes',
            required: false,
          ),
      ],
      save: (d) async {
        await ApiService.businessRequest(
          row == null
              ? '/api/fixed-expenses'
              : '/api/fixed-expenses/${row['id']}',
          method: row == null ? 'POST' : 'PUT',
          body: d,
        );
      },
    );
    if (saved == true) await load();
  }

  Future<void> pay(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الدفع'),
        content: Text(
          '${row['title']} • ${monthLabel(month)}\n${amount(row['amount'])}\nيُضاف للمصاريف مرة واحدة بتاريخ الدفع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الدفع'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy.add(row['id']));
    try {
      await ApiService.businessRequest(
        '/api/fixed-expenses/${row['id']}/pay',
        method: 'POST',
        body: {'month': monthLabel(month)},
      );
      await load();
    } catch (e) {
      notice(e);
    }
    if (mounted) setState(() => busy.remove(row['id']));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الالتزامات والمدفوعات الثابتة')),
      body: !appPermissions.canManageHR
          ? const Center(child: Text('هذه الصفحة متاحة للمالك والمطور.'))
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'الإيجارات والاشتراكات والخدمات الشهرية',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'المبالغ المستحقة لا تُخصم من الربح حتى تسجيل دفعها. الرواتب تُدار من الموارد البشرية.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة التزام'),
                      ),
                      IconButton(
                        onPressed: loading
                            ? null
                            : () {
                                setState(
                                  () => month = DateTime(
                                    month.year,
                                    month.month - 1,
                                  ),
                                );
                                load();
                              },
                        icon: const Icon(Icons.chevron_right),
                      ),
                      Text(monthLabel(month)),
                      IconButton(
                        onPressed: loading
                            ? null
                            : () {
                                setState(
                                  () => month = DateTime(
                                    month.year,
                                    month.month + 1,
                                  ),
                                );
                                load();
                              },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        onPressed: loading ? null : load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (!loading && error == null) ...[
                    Text(
                      'غير المدفوع للشهر: ${amount(rows.where((r) => r['active'] == true && r['paid'] != true).fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble()))}',
                    ),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('لا توجد التزامات مسجلة بعد.'),
                      ),
                    for (final r in rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['title']} • ${r['category']}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${amount(r['amount'])} • الاستحقاق يوم ${r['due_day']}',
                              ),
                              Text(
                                r['paid'] == true
                                    ? 'مدفوع: ${amount(r['paid_amount'])}'
                                    : r['active'] == true
                                    ? 'غير مدفوع'
                                    : 'متوقف',
                              ),
                              Wrap(
                                spacing: 12,
                                children: [
                                  TextButton(
                                    onPressed: () => edit(r),
                                    child: const Text('تعديل'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await ApiService.businessRequest(
                                          '/api/fixed-expenses/${r['id']}',
                                          method: 'PUT',
                                          body: {'active': r['active'] != true},
                                        );
                                        await load();
                                      } catch (e) {
                                        notice(e);
                                      }
                                    },
                                    child: Text(
                                      r['active'] == true
                                          ? 'إيقاف الالتزام'
                                          : 'تفعيل',
                                    ),
                                  ),
                                  if (r['active'] == true && r['paid'] != true)
                                    FilledButton(
                                      onPressed: busy.contains(r['id'])
                                          ? null
                                          : () => pay(r),
                                      child: const Text('تسجيل الدفع'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    ),
  );
}
