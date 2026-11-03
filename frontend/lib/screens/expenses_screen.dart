import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/expense_model.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../widgets/section_tabs.dart';
import '../widgets/business_form.dart';
import '../services/permissions_service.dart';
import 'fixed_expenses_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _search = TextEditingController();
  List<ExpenseModel> _expenses = [];
  bool _loading = true;
  String? _error, _category;
  String _period = 'all', _sort = 'newest';
  DateTimeRange? _range;
  int _page = 0, _periodRevision = 0;
  int _mobileSection = 0;
  int _loadVersion = 0;
  final Set<int> _deleting = {};
  static const _pageSize = 20;
  static const _periods = {
    'all': 'كل الفترات',
    'today': 'اليوم',
    'week': 'آخر 7 أيام',
    'month': 'هذا الشهر',
    'year': 'هذه السنة',
    'custom': 'فترة مخصصة',
  };

  @override
  void initState() {
    super.initState();
    ThemeService.themeModeNotifier.addListener(_themeChanged);
    ApiService.reportsRevision.addListener(_loadExpenses);
    _loadExpenses();
  }

  void _themeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeService.themeModeNotifier.removeListener(_themeChanged);
    ApiService.reportsRevision.removeListener(_loadExpenses);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    if (!mounted || !appPermissions.canManageExpenses) return;
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getExpenses();
      final expenses = (data['expenses'] as List)
          .map((e) => ExpenseModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _expenses = expenses;
        _loading = false;
        _page = 0;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _error =
            'تعذر تحديث المصاريف. تحقق من الاتصال بالسيرفر ثم أعد المحاولة.';
      });
    }
  }

  List<ExpenseModel> _filteredExpenses() {
    final now = DateTime.now();
    DateTime? start, end;
    switch (_period) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day + 1);
      case 'week':
        start = DateTime(now.year, now.month, now.day - 6);
        end = DateTime(now.year, now.month, now.day + 1);
      case 'month':
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1);
      case 'year':
        start = DateTime(now.year);
        end = DateTime(now.year + 1);
      case 'custom':
        start = _range?.start;
        final last = _range?.end;
        if (last != null) end = DateTime(last.year, last.month, last.day + 1);
    }
    final result = _expenses
        .where(
          (e) => e.matches(
            query: _search.text,
            category: _category,
            start: start,
            endExclusive: end,
          ),
        )
        .toList();
    result.sort((a, b) {
      if (_sort == 'highest') {
        final amount = b.amount.compareTo(a.amount);
        if (amount != 0) return amount;
      }
      final date = (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      );
      final comparison = date == 0 ? b.id.compareTo(a.id) : date;
      return _sort == 'oldest' ? -comparison : comparison;
    });
    return result;
  }

  String _date(DateTime? date, {bool time = false}) {
    if (date == null) return 'تاريخ غير متوفر';
    String two(int n) => '$n'.padLeft(2, '0');
    final day = '${date.year}/${two(date.month)}/${two(date.day)}';
    return time ? '$day • ${two(date.hour)}:${two(date.minute)}' : day;
  }

  String get _periodLabel => _period == 'custom' && _range != null
      ? '${_date(_range!.start)} — ${_date(_range!.end)}'
      : _periods[_period]!;
  Future<void> _choosePeriod(String value) async {
    if (value == 'custom') {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _range,
        helpText: 'اختر فترة المصاريف',
        saveText: 'تطبيق',
        cancelText: 'إلغاء',
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
      );
      if (!mounted) return;
      setState(() {
        _periodRevision++;
        if (range != null) {
          _range = range;
          _period = value;
          _page = 0;
        }
      });
    } else {
      setState(() {
        _period = value;
        _page = 0;
      });
    }
  }

  Future<void> _addExpense() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddExpenseDialog(),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم حفظ المصروف. يظهر في السجل إذا كان يطابق الفلاتر المحددة.',
        ),
      ),
    );
    await _loadExpenses();
  }

  Future<void> _deleteExpense(ExpenseModel expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المصروف؟'),
          content: Text(
            'سيتم حذف «${expense.title}» بقيمة ${expenseMoney(expense.amount)} من السجل. لا يمكن التراجع عن الحذف.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف المصروف'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true || _deleting.contains(expense.id)) return;
    setState(() => _deleting.add(expense.id));
    final success = await ApiService.deleteExpense(expense.id);
    if (!mounted) return;
    setState(() {
      _deleting.remove(expense.id);
      if (success) {
        _expenses.removeWhere((e) => e.id == expense.id);
        _page = 0;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'تم حذف المصروف'
              : 'تعذر حذف المصروف. تحقق من الاتصال ثم أعد المحاولة.',
        ),
      ),
    );
  }

  Future<void> _editExpense(ExpenseModel expense) async {
    final saved = await businessForm(
      context,
      title: 'تعديل المصروف',
      initial: {
        'title': expense.title,
        'amount': expense.amount,
        'category': expense.category,
        'notes': expense.notes,
      },
      fields: const [
        BusinessField('title', 'العنوان'),
        BusinessField('amount', 'المبلغ', kind: 'number'),
        BusinessField('category', 'التصنيف'),
        BusinessField('notes', 'ملاحظات', kind: 'notes', required: false),
      ],
      save: (body) async {
        await ApiService.businessRequest(
          '/api/expenses/${expense.id}',
          method: 'PUT',
          body: body,
        );
      },
    );
    if (saved == true) await _loadExpenses();
  }

  void _showDetails(ExpenseModel expense) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل المصروف #${expense.id}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    expense.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    expenseMoney(expense.amount),
                    style: TextStyle(
                      fontSize: 28,
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(height: 32),
                  Text('التصنيف: ${expense.category}'),
                  const SizedBox(height: 12),
                  Text('سجّله: ${expense.createdBy}'),
                  const SizedBox(height: 12),
                  Text(
                    'التاريخ والوقت المحلي: ${_date(expense.createdAt, time: true)}',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'الملاحظات',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    expense.notes.isEmpty ? 'لا توجد ملاحظات' : expense.notes,
                  ),
                ],
              ),
            ),
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
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
  Widget _metric(
    String title,
    String value,
    String caption,
    IconData icon,
    Color color,
  ) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          value,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
  InputDecoration _input(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: AppColors.surfaceVariant,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.border),
    ),
  );

  Widget _filters(double width) {
    final categories = {
      ..._expenses.map((e) => e.category),
      ?_category,
    }.toList()..sort();
    final fieldWidth = width > 900
        ? (width - 78) / 4
        : width > 540
        ? (width - 54) / 2
        : width - 42;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() => _page = 0),
                  decoration: _input('بحث في المصاريف', Icons.search),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: _period,
                  key: ValueKey('period-$_period-$_periodRevision'),
                  isExpanded: true,
                  decoration: _input('الفترة', Icons.date_range_outlined),
                  items: _periods.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _choosePeriod(value);
                  },
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: _category ?? '',
                  key: ValueKey('category-$_category'),
                  isExpanded: true,
                  decoration: _input('التصنيف', Icons.category_outlined),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('كل التصنيفات'),
                    ),
                    ...categories.map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _category = value == '' ? null : value;
                    _page = 0;
                  }),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: _input('ترتيب السجل', Icons.sort),
                  items: const [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('الأحدث أولاً'),
                    ),
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text('الأقدم أولاً'),
                    ),
                    DropdownMenuItem(
                      value: 'highest',
                      child: Text('الأعلى مبلغاً'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _sort = value!;
                    _page = 0;
                  }),
                ),
              ),
            ],
          ),
          if (_period != 'all' || _category != null || _search.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    'الفترة المعروضة: $_periodLabel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  if (_period == 'custom')
                    TextButton(
                      onPressed: () => _choosePeriod('custom'),
                      child: const Text('تغيير التاريخ'),
                    ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _search.clear();
                      _category = null;
                      _period = 'all';
                      _page = 0;
                    }),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('مسح الفلاتر'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _breakdown(List<ExpenseModel> expenses, double total) {
    final totals = <String, double>{};
    for (final expense in expenses) {
      totals.update(
        expense.category,
        (v) => v + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = sorted.take(5).toList();
    if (sorted.length > 5) {
      shown.add(
        MapEntry(
          'بقية التصنيفات (${sorted.length - 5})',
          sorted.skip(5).fold(0.0, (sum, e) => sum + e.value),
        ),
      );
    }
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'توزيع المصاريف',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'حسب النتائج المحددة',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          for (final entry in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      const SizedBox(width: 8),
                      Text(
                        '${(entry.value / total * 100).toStringAsFixed(1)}٪',
                        style: TextStyle(color: AppColors.primaryLight),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (entry.value / total).clamp(0, 1),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    color: AppColors.primaryLight,
                    backgroundColor: AppColors.background,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    expenseMoney(entry.value),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _record(ExpenseModel expense, bool wide) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          expense.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          '#${expense.id} • ${expense.category}',
          style: TextStyle(color: AppColors.primaryLight, fontSize: 12),
        ),
        if (!wide) ...[
          const SizedBox(height: 8),
          Text(
            '${_date(expense.createdAt, time: true)} • ${expense.createdBy}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ],
    );
    final amount = Text(
      expenseMoney(expense.amount),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'عرض تفاصيل المصروف',
          icon: Icon(
            Icons.open_in_new,
            size: 19,
            color: AppColors.primaryLight,
          ),
          onPressed: () => _showDetails(expense),
        ),
        if (expense.editable)
          IconButton(
            tooltip: 'تعديل المصروف',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _editExpense(expense),
          ),
        _deleting.contains(expense.id)
            ? const SizedBox(
                width: 48,
                height: 24,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : IconButton(
                tooltip: 'حذف المصروف',
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppColors.danger,
                ),
                onPressed: expense.editable
                    ? () => _deleteExpense(expense)
                    : null,
              ),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDetails(expense),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: wide
              ? Row(
                  children: [
                    Expanded(flex: 4, child: details),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _date(expense.createdAt, time: true),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        expense.createdBy,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(flex: 3, child: amount),
                    actions,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    details,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: amount),
                        actions,
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _records(List<ExpenseModel> expenses) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 780;
      final pageCount = (expenses.length / _pageSize).ceil();
      final currentPage = _page.clamp(0, pageCount - 1);
      final start = currentPage * _pageSize;
      final page = expenses.skip(start).take(_pageSize).toList();
      return _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'سجل المصاريف',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${expenses.length} مصروف',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (wide)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                color: AppColors.surfaceVariant,
                child: const Row(
                  children: [
                    Expanded(flex: 4, child: Text('المصروف / التصنيف')),
                    Expanded(flex: 3, child: Text('التاريخ والوقت')),
                    Expanded(flex: 2, child: Text('سجّله')),
                    Expanded(flex: 3, child: Text('المبلغ')),
                    SizedBox(width: 96, child: Text('الإجراءات')),
                  ],
                ),
              ),
            for (final expense in page) ...[
              _record(expense, wide),
              Divider(height: 1, color: AppColors.border),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'عرض ${start + 1}–${start + page.length} من ${expenses.length}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'الصفحة السابقة',
                      onPressed: currentPage > 0
                          ? () => setState(() => _page = currentPage - 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    Text('${currentPage + 1} / $pageCount'),
                    IconButton(
                      tooltip: 'الصفحة التالية',
                      onPressed: currentPage + 1 < pageCount
                          ? () => setState(() => _page = currentPage + 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (!appPermissions.canManageExpenses)
      return const Center(child: Text('هذه الصفحة متاحة للإدارة فقط.'));
    final expenses = _filteredExpenses();
    final total = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final largest = expenses.fold(
      0.0,
      (value, e) => e.amount > value ? e.amount : value,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 600 ? 12.0 : 24.0;
            final width = constraints.maxWidth - padding * 2;
            final columns = width >= 950
                ? 4
                : width >= 560
                ? 2
                : 1;
            final metricWidth = (width - (columns - 1) * 12) / columns;
            return RefreshIndicator(
              onRefresh: _loadExpenses,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 24,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المصاريف',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'سجّل مصاريفك وتابع أين تذهب أموال العمل',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: _addExpense,
                          icon: const Icon(Icons.add),
                          label: const Text('تسجيل مصروف'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _loading ? null : _loadExpenses,
                          tooltip: 'تحديث المصاريف',
                          icon: const Icon(Icons.refresh),
                        ),
                        if (appPermissions.canManageHR)
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FixedExpensesScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.event_repeat),
                            label: const Text('الالتزامات الشهرية'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _filters(width),
                    const SizedBox(height: 18),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _panel(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _error!,
                                style: const TextStyle(color: AppColors.danger),
                              ),
                              if (_expenses.isNotEmpty)
                                const Text(
                                  'البيانات الظاهرة من آخر تحميل ناجح.',
                                ),
                              TextButton.icon(
                                onPressed: _loading ? null : _loadExpenses,
                                icon: const Icon(Icons.refresh),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if ((!_loading || _expenses.isNotEmpty) &&
                        (_error == null || _expenses.isNotEmpty)) ...[
                      if (width < 650)
                        SectionTabs(
                          labels: const ['السجل', 'الملخص', 'التصنيفات'],
                          selected: _mobileSection,
                          onSelected: (value) =>
                              setState(() => _mobileSection = value),
                        ),
                      if (width >= 650 || _mobileSection == 1)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: metricWidth,
                              child: _metric(
                                'إجمالي المصاريف',
                                expenseMoney(total),
                                'حسب البحث والفترة والتصنيف',
                                Icons.account_balance_wallet_outlined,
                                AppColors.primaryLight,
                              ),
                            ),
                            SizedBox(
                              width: metricWidth,
                              child: _metric(
                                'عدد المصاريف',
                                '${expenses.length}',
                                'في النتائج المعروضة',
                                Icons.receipt_long_outlined,
                                AppColors.primaryLight,
                              ),
                            ),
                            SizedBox(
                              width: metricWidth,
                              child: _metric(
                                'متوسط المصروف',
                                expenseMoney(
                                  expenses.isEmpty
                                      ? 0
                                      : total / expenses.length,
                                ),
                                'الإجمالي ÷ عدد المصاريف',
                                Icons.equalizer,
                                AppColors.historyIcon,
                              ),
                            ),
                            SizedBox(
                              width: metricWidth,
                              child: _metric(
                                'أعلى مصروف',
                                expenseMoney(largest),
                                'أكبر مبلغ ضمن النتائج',
                                Icons.trending_up,
                                AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      if (expenses.isEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: _panel(
                            Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 48,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _expenses.isEmpty
                                      ? 'ابدأ بتسجيل أول مصروف'
                                      : 'لا توجد مصاريف تطابق البحث',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _expenses.isEmpty
                                      ? 'أضف الإيجار والرواتب وبقية المصاريف لتظهر هنا.'
                                      : 'غيّر الفترة أو التصنيف أو كلمة البحث.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                if (_expenses.isEmpty)
                                  TextButton(
                                    onPressed: _addExpense,
                                    child: const Text('تسجيل مصروف جديد'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      else if (width >= 1250 && total > 0)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _records(expenses)),
                            const SizedBox(width: 20),
                            SizedBox(
                              width: 280,
                              child: _breakdown(expenses, total),
                            ),
                          ],
                        )
                      else ...[
                        if (width >= 650 || _mobileSection == 0)
                          _records(expenses),
                        if (total > 0 &&
                            (width >= 650 || _mobileSection == 2)) ...[
                          const SizedBox(height: 20),
                          _breakdown(expenses, total),
                        ],
                      ],
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'المبالغ بالدينار العراقي • التواريخ حسب التوقيت المحلي لجهازك',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog();
  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _category = TextEditingController(text: 'عام');
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await ApiService.addExpense(
      _title.text.trim(),
      parseExpenseAmount(_amount.text)!,
      _category.text.trim(),
      _notes.text.trim(),
    );
    if (!mounted) return;
    if (saved) {
      setState(() => _saving = false);
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = 'لم يتم تأكيد الحفظ. تحقق من الاتصال ثم أعد المحاولة.';
      });
    }
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تسجيل مصروف جديد'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أدخل المبلغ والتصنيف. يُسجَّل التاريخ والموظف تلقائياً.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _title,
                    autofocus: true,
                    enabled: !_saving,
                    maxLength: 150,
                    decoration: _decoration(
                      'عنوان المصروف *',
                      Icons.receipt_long_outlined,
                      hint: 'مثلاً: إيجار المحل',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل عنوان المصروف'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amount,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration(
                      'المبلغ بالدينار العراقي *',
                      Icons.payments_outlined,
                      hint: 'مثلاً: 25,000',
                    ),
                    validator: (value) =>
                        parseExpenseAmount(value ?? '') == null
                        ? 'أدخل مبلغاً موجباً صحيحاً (حتى منزلتين عشريتين)'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _category,
                    enabled: !_saving,
                    maxLength: 80,
                    decoration: _decoration(
                      'التصنيف *',
                      Icons.category_outlined,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل التصنيف أو اختره أدناه'
                        : null,
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in [
                        'عام',
                        'إيجار',
                        'رواتب',
                        'اشتراكات',
                        'مدفوعات ثابتة',
                        'خدمات',
                        'كهرباء',
                        'صيانة',
                        'نقل',
                        'مستلزمات',
                      ])
                        ActionChip(
                          label: Text(category),
                          onPressed: _saving
                              ? null
                              : () => _category.text = category,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _notes,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 255,
                    decoration: _decoration(
                      'ملاحظات (اختياري)',
                      Icons.notes_outlined,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ المصروف'),
          ),
        ],
      ),
    ),
  );
}
