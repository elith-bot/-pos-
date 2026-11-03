import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';
import '../models/expense_model.dart';
import '../widgets/business_form.dart';
import '../widgets/section_tabs.dart';

const payTypes = {'monthly': 'شهري', 'daily': 'يومي', 'hourly': 'بالساعة'};
const attendanceTypes = {
  'present': 'حاضر',
  'absent': 'غائب',
  'leave': 'إجازة',
  'holiday': 'عطلة',
};
const bonusTypes = {
  'none': 'بدون مكافأة تلقائية',
  'monthly': 'مبلغ ثابت شهرياً',
  'per_present_day': 'مبلغ عن كل يوم حضور',
};
String monthLabel(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
String dayLabel(DateTime d) => d.toIso8601String().substring(0, 10);
String amount(dynamic v) => expenseMoney((v as num? ?? 0).toDouble());

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  int section = 0, version = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> staff = [], attendance = [], payroll = [];
  String search = '';
  bool loading = true;
  String? error;
  final busyIds = <int>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!appPermissions.canManageHR) return;
    final requestVersion = ++version;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.businessRequest('/api/hr/staff'),
        ApiService.businessRequest(
          '/api/hr/attendance',
          query: {'month': monthLabel(month)},
        ),
        ApiService.businessRequest(
          '/api/hr/payroll',
          query: {'month': monthLabel(month)},
        ),
      ]);
      if (!mounted || requestVersion != version) return;
      setState(() {
        staff = List<Map<String, dynamic>>.from(results[0]['staff']);
        attendance = List<Map<String, dynamic>>.from(results[1]['attendance']);
        payroll = List<Map<String, dynamic>>.from(results[2]['payroll']);
        loading = false;
      });
    } catch (e) {
      if (mounted && requestVersion == version)
        setState(() {
          loading = false;
          error = e.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  void notify(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
  }

  Future<void> editStaff([Map<String, dynamic>? s]) async {
    try {
      final users = await ApiService.getUsers();
      if (!mounted) return;
      final c = Map<String, dynamic>.from(s?['contract'] ?? {});
      final saved = await businessForm(
        context,
        title: s == null ? 'إضافة موظف وعقد العمل' : 'تعديل الموظف والعقد',
        description:
            'ملف الموارد البشرية مستقل عن حساب الدخول. اربطه بحساب ليتمكن صاحبه من رؤية عقده. قواعد الحضور تحتسب من السجلات المدخلة فقط؛ الأيام غير المسجلة لا تعتبر غياباً. الراتب الشهري لا يُجزأ تلقائياً عند التعيين منتصف الشهر. الدوام هنا ضمن اليوم نفسه.',
        initial: {
          'start_date': dayLabel(DateTime.now()),
          'rate': 0,
          'grace_minutes': 0,
          'late_per_minute': 0,
          'absence_per_day': 0,
          'fixed_deduction': 0,
          'bonus_amount': 0,
          'effective_month': monthLabel(month),
          'workdays': '0,1,2,3,4,5',
          'shift_start': '09:00',
          'shift_end': '17:00',
          ...?s,
          ...c,
          'user_id': '${s?['user_id'] ?? 0}',
        },
        fields: [
          const BusinessField('name', 'الاسم الكامل'),
          const BusinessField('job_title', 'المسمى الوظيفي', required: false),
          const BusinessField('phone', 'الهاتف', required: false),
          const BusinessField('start_date', 'تاريخ التعيين', kind: 'date'),
          BusinessField(
            'user_id',
            'حساب الدخول المرتبط',
            options: {
              '0': 'بدون حساب دخول',
              for (final u in users) '${u.id}': '${u.fullName} (${u.username})',
            },
          ),
          const BusinessField(
            'pay_type',
            'نوع الراتب / الأجر',
            options: payTypes,
          ),
          const BusinessField(
            'rate',
            'مبلغ الأجر حسب النوع (د.ع)',
            kind: 'number',
          ),
          const BusinessField('effective_month', 'شهر سريان العقد YYYY-MM'),
          const BusinessField('shift_start', 'بداية الدوام HH:MM'),
          const BusinessField('shift_end', 'نهاية الدوام HH:MM'),
          const BusinessField(
            'workdays',
            'أيام الدوام: 0 الاثنين … 6 الأحد، بفواصل',
          ),
          const BusinessField(
            'grace_minutes',
            'سماح التأخير (دقائق)',
            kind: 'number',
          ),
          const BusinessField(
            'late_per_minute',
            'خصم كل دقيقة تأخير بعد السماح',
            kind: 'number',
          ),
          const BusinessField(
            'absence_per_day',
            'خصم يوم الغياب المسجّل',
            kind: 'number',
          ),
          const BusinessField(
            'fixed_deduction',
            'خصم شهري ثابت',
            kind: 'number',
          ),
          const BusinessField(
            'bonus_type',
            'نظام المكافآت',
            options: bonusTypes,
          ),
          const BusinessField(
            'bonus_amount',
            'مبلغ المكافأة حسب النظام',
            kind: 'number',
          ),
          const BusinessField(
            'contract_notes',
            'شروط العقد والإجازات وباقي الاتفاقات',
            kind: 'notes',
            required: false,
          ),
          const BusinessField(
            'notes',
            'ملاحظات إدارية خاصة (لا تظهر للموظف)',
            kind: 'notes',
            required: false,
          ),
        ],
        save: (d) async {
          final contractKeys = [
            'pay_type',
            'rate',
            'effective_month',
            'shift_start',
            'shift_end',
            'workdays',
            'grace_minutes',
            'late_per_minute',
            'absence_per_day',
            'fixed_deduction',
            'bonus_type',
            'bonus_amount',
            'contract_notes',
          ];
          final body = <String, dynamic>{
            for (final k in [
              'name',
              'job_title',
              'phone',
              'start_date',
              'user_id',
              'notes',
            ])
              k: d[k],
            'base_salary': d['rate'],
            'contract': {for (final k in contractKeys) k: d[k]},
          };
          await ApiService.businessRequest(
            s == null ? '/api/hr/staff' : '/api/hr/staff/${s['id']}',
            method: s == null ? 'POST' : 'PUT',
            body: body,
          );
        },
      );
      if (saved == true) await load();
    } catch (e) {
      notify(e);
    }
  }

  Future<void> recordAttendance([Map<String, dynamic>? row]) async {
    final available = staff.where((s) => s['active'] == true).toList();
    if (available.isEmpty) {
      notify('أضف موظفاً نشطاً أولاً.');
      return;
    }
    final saved = await businessForm(
      context,
      title: 'تسجيل / تعديل الحضور',
      description:
          'يمكن حفظ الدخول أولاً وإضافة الخروج لاحقاً. الأجر بالساعة يعتمد على الساعات المكتملة فقط. الحفظ لنفس الموظف واليوم يعدّل السجل الحالي.',
      initial: {
        'day': dayLabel(DateTime.now()),
        ...?row,
        if (row != null) 'staff_id': '${row['staff_id']}',
      },
      fields: [
        BusinessField(
          'staff_id',
          'الموظف',
          options: {for (final s in available) '${s['id']}': '${s['name']}'},
        ),
        const BusinessField('day', 'التاريخ', kind: 'date'),
        const BusinessField('status', 'الحالة', options: attendanceTypes),
        const BusinessField('check_in', 'الدخول HH:MM', required: false),
        const BusinessField('check_out', 'الخروج HH:MM', required: false),
        const BusinessField('notes', 'ملاحظات', kind: 'notes', required: false),
      ],
      save: (d) async {
        await ApiService.businessRequest(
          '/api/hr/attendance',
          method: 'POST',
          body: d,
        );
      },
    );
    if (saved == true) await load();
  }

  Future<void> preparePayroll(
    Map<String, dynamic> s, [
    Map<String, dynamic>? row,
  ]) async {
    try {
      final preview = await ApiService.businessRequest(
        '/api/hr/staff/${s['id']}/payroll-preview',
        query: {'month': monthLabel(month)},
      );
      final c = preview['calculation'] as Map;
      if (!mounted) return;
      final old = row?['calculation'] as Map? ?? {};
      final saved = await businessForm(
        context,
        title: 'إعداد راتب ${s['name']} • ${monthLabel(month)}',
        description:
            'الأجر المحسوب: ${amount(c['base_salary'])}\nحضور: ${c['present_days']} يوم • عمل: ${c['worked_hours']} ساعة • تأخير: ${c['late_minutes']} دقيقة\nمكافآت العقد: ${amount(c['automatic_bonus'])}\nخصومات العقد: ${amount(c['automatic_deduction'])}\nراجع الحضور والعقد قبل الصرف. الحساب يُراجع مجدداً في السيرفر.',
        initial: {
          'bonus': old['manual_bonus'] ?? 0,
          'deduction': old['manual_deduction'] ?? 0,
          'notes': row?['notes'] ?? '',
        },
        fields: const [
          BusinessField('bonus', 'مكافأة إضافية يدوية', kind: 'number'),
          BusinessField('deduction', 'خصم إضافي يدوي', kind: 'number'),
          BusinessField(
            'notes',
            'سبب التعديلات وملاحظات الراتب',
            kind: 'notes',
            required: false,
          ),
        ],
        save: (d) async {
          await ApiService.businessRequest(
            '/api/hr/payroll',
            method: 'POST',
            body: {...d, 'staff_id': s['id'], 'month': monthLabel(month)},
          );
        },
      );
      if (saved == true) await load();
    } catch (e) {
      notify(e);
    }
  }

  Future<void> pay(Map<String, dynamic> p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد صرف الراتب'),
        content: Text(
          '${p['staff_name']} • ${p['month']}\nالصافي: ${amount(p['net_salary'])}\nسيُسجّل بالمصاريف مرة واحدة، وتُقفل تفاصيل الراتب وحضور هذا الشهر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الصرف'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busyIds.add(p['id']));
    try {
      await ApiService.businessRequest(
        '/api/hr/payroll/${p['id']}/pay',
        method: 'POST',
        body: {},
      );
      await load();
    } catch (e) {
      notify(e);
    }
    if (mounted) setState(() => busyIds.remove(p['id']));
  }

  Widget panel(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
  @override
  Widget build(BuildContext context) {
    if (!appPermissions.canManageHR)
      return const Center(
        child: Text('إدارة الموارد البشرية متاحة للمالك والمطور.'),
      );
    final people = staff
        .where((s) => '${s['name']} ${s['job_title']}'.contains(search))
        .toList();
    final paid = payroll
        .where((p) => p['status'] == 'paid')
        .fold<double>(0, (v, p) => v + (p['net_salary'] as num).toDouble());
    final due = payroll
        .where((p) => p['status'] == 'draft')
        .fold<double>(0, (v, p) => v + (p['net_salary'] as num).toDouble());
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'الموارد البشرية',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                FilledButton.icon(
                  onPressed: () => editStaff(),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('إضافة موظف وعقد'),
                ),
                IconButton(
                  onPressed: loading ? null : load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'الموظفون النشطون: ${staff.where((s) => s['active'] == true).length}',
                  ),
                ),
                Chip(label: Text('مصروف الرواتب: ${amount(paid)}')),
                Chip(label: Text('مسودات غير مصروفة: ${amount(due)}')),
              ],
            ),
            Row(
              children: [
                IconButton(
                  onPressed: loading
                      ? null
                      : () {
                          setState(
                            () => month = DateTime(month.year, month.month - 1),
                          );
                          load();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
                Text(
                  monthLabel(month),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: loading
                      ? null
                      : () {
                          setState(
                            () => month = DateTime(month.year, month.month + 1),
                          );
                          load();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            SectionTabs(
              labels: const ['الموظفون والعقود', 'الحضور والإجازات', 'الرواتب'],
              selected: section,
              onSelected: (i) => setState(() => section = i),
            ),
            const SizedBox(height: 12),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              panel(Text(error!, style: const TextStyle(color: Colors.red))),
            if (!loading && error == null) ...[
              if (section == 0) ...[
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'البحث عن موظف',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
                const SizedBox(height: 12),
                if (people.isEmpty)
                  panel(
                    const Text(
                      'أضف موظفاً وحدد عقده، ويمكن ربطه بحساب الدخول الحالي.',
                    ),
                  ),
                for (final s in people)
                  panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s['name']} • ${s['job_title']}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${s['active'] == true ? 'نشط' : 'مؤرشف'} • التعيين: ${s['start_date']} • ${s['phone']}',
                        ),
                        Text(
                          'الأجر ${payTypes[s['contract']['pay_type']] ?? ''}: ${amount(s['contract']['rate'])}',
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => editStaff(s),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('تعديل البيانات والعقد'),
                            ),
                            TextButton(
                              onPressed: () => showContract(
                                context,
                                s['contract'],
                                title: 'عقد ${s['name']}',
                              ),
                              child: const Text('عرض العقد'),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  await ApiService.businessRequest(
                                    '/api/hr/staff/${s['id']}',
                                    method: 'PUT',
                                    body: {'active': s['active'] != true},
                                  );
                                  await load();
                                } catch (e) {
                                  notify(e);
                                }
                              },
                              child: Text(
                                s['active'] == true
                                    ? 'أرشفة الموظف'
                                    : 'إعادة التفعيل',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
              if (section == 1) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: () => recordAttendance(),
                    icon: const Icon(Icons.event_available),
                    label: const Text('تسجيل حضور / إجازة'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'حضور: ${attendance.where((a) => a['status'] == 'present').length} • غياب: ${attendance.where((a) => a['status'] == 'absent').length} • إجازات: ${attendance.where((a) => a['status'] == 'leave').length}',
                ),
                if (attendance.isEmpty)
                  panel(const Text('لا توجد سجلات حضور لهذا الشهر.')),
                for (final a in attendance)
                  panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a['staff_name']} • ${a['day']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${attendanceTypes[a['status']]} • ${a['check_in']} — ${a['check_out']}',
                        ),
                        Text('${a['notes']}'),
                        TextButton(
                          onPressed: () => recordAttendance(a),
                          child: const Text('تعديل الحضور'),
                        ),
                      ],
                    ),
                  ),
              ],
              if (section == 2) ...[
                const Text(
                  'يُحسب الراتب من العقد الساري والحضور المسجل. حفظ المسودة لا يُسجل مصروفاً؛ تأكيد الصرف فقط يسجله بتاريخ الدفع.',
                ),
                const SizedBox(height: 12),
                for (final s in people.where(
                  (s) =>
                      s['active'] == true ||
                      payroll.any((p) => p['staff_id'] == s['id']),
                ))
                  Builder(
                    builder: (_) {
                      final p = payroll
                          .where((p) => p['staff_id'] == s['id'])
                          .firstOrNull;
                      return panel(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s['name']}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (p == null)
                              const Text('لم يُعدّ راتب هذا الشهر')
                            else ...[
                              Text(
                                'الأجر: ${amount(p['base_salary'])} • المكافآت: ${amount(p['bonus'])} • الخصومات: ${amount(p['deduction'])}',
                              ),
                              Text(
                                'الصافي: ${amount(p['net_salary'])}',
                                style: TextStyle(
                                  color: AppColors.primaryLight,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                p['status'] == 'paid'
                                    ? 'تم الصرف • ${p['paid_at']}'
                                    : 'مسودة قيد المراجعة',
                              ),
                              Text('${p['notes']}'),
                              TextButton(
                                onPressed: () => showContract(
                                  context,
                                  p['calculation']['contract'] ?? {},
                                  title: 'العقد المعتمد في راتب ${p['month']}',
                                ),
                                child: const Text('العقد المعتمد بالحساب'),
                              ),
                            ],
                            if (p?['status'] != 'paid')
                              Wrap(
                                spacing: 12,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => preparePayroll(s, p),
                                    child: Text(
                                      p == null
                                          ? 'إعداد الراتب'
                                          : 'إعادة حساب / تعديل',
                                    ),
                                  ),
                                  if (p != null)
                                    FilledButton(
                                      onPressed: busyIds.contains(p['id'])
                                          ? null
                                          : () => pay(p),
                                      child: const Text('صرف الراتب'),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Widget contractDetails(Map c) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('السريان: ${c['effective_month']}'),
    Text('نوع الأجر: ${payTypes[c['pay_type']] ?? ''} • ${amount(c['rate'])}'),
    Text('الدوام: ${c['shift_start']} — ${c['shift_end']}'),
    Text('أيام العمل (0 الاثنين … 6 الأحد): ${c['workdays']}'),
    Text(
      'السماح: ${c['grace_minutes']} دقيقة • خصم الدقيقة: ${amount(c['late_per_minute'])}',
    ),
    Text(
      'خصم الغياب المسجل: ${amount(c['absence_per_day'])} • خصم ثابت: ${amount(c['fixed_deduction'])}',
    ),
    Text(
      'المكافآت: ${bonusTypes[c['bonus_type']] ?? ''} • ${amount(c['bonus_amount'])}',
    ),
    const Divider(),
    Text('${c['contract_notes'] ?? ''}'),
  ],
);
Future<void> showContract(
  BuildContext context,
  Map c, {
  String title = 'العقد وشروط العمل',
}) => showDialog<void>(
  context: context,
  builder: (ctx) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(child: contractDetails(c)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  ),
);

class MyContractScreen extends StatefulWidget {
  const MyContractScreen({super.key});
  @override
  State<MyContractScreen> createState() => _MyContractScreenState();
}

class _MyContractScreenState extends State<MyContractScreen> {
  late Future<Map<String, dynamic>> result = ApiService.businessRequest(
    '/api/hr/my-contract',
  );
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('عقدي وشروط العمل'),
        actions: [
          IconButton(
            onPressed: () => setState(
              () => result = ApiService.businessRequest('/api/hr/my-contract'),
            ),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: result,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: Text('${snapshot.error}'.replaceFirst('Exception: ', '')),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final d = snapshot.data!;
          if (d['staff'] == null)
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا يوجد عقد مرتبط بحسابك بعد. اطلب من الإدارة ربط ملف الموظف بحساب الدخول.',
                ),
              ),
            );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${d['staff']['name']} • ${d['staff']['job_title']}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text('نسخة للعرض فقط. التعديلات من الإدارة المخولة.'),
              for (final c in d['contracts'])
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: contractDetails(c),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
