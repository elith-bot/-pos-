import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../widgets/section_tabs.dart';
import '../widgets/sale_details_dialog.dart';
import '../services/permissions_service.dart';
import '../widgets/export_menu.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.isActive = true});
  final bool isActive;
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Timer? _refreshTimer;
  bool loading = true;
  String? error;
  int _loadVersion = 0;
  int _mobileSection = 0;
  String period = 'today';
  DateTime? start, end;
  double hours = 4;
  Map<String, dynamic> data = {};
  final periods = const {
    'today': 'اليوم',
    'yesterday': 'أمس',
    'week': 'آخر 7 أيام',
    'month': 'هذا الشهر',
    'year': 'هذه السنة',
    'all': 'كل الفترات',
    'custom': 'مخصصة',
    'hours': 'ساعات مخصصة',
  };

  @override
  void initState() {
    super.initState();
    ThemeService.themeModeNotifier.addListener(themeChanged);
    ApiService.reportsRevision.addListener(_reportsChanged);
    if (widget.isActive) load();
    _configureRefresh();
  }

  @override
  void didUpdateWidget(covariant AnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _configureRefresh();
      if (widget.isActive) load(silent: data.isNotEmpty);
    }
  }

  void _configureRefresh() {
    _refreshTimer?.cancel();
    if (widget.isActive && appPermissions.canViewGeneralStats) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!loading) load(silent: true);
      });
    }
  }

  void _reportsChanged() {
    if (widget.isActive) load(silent: true);
  }

  void themeChanged() {
    if (mounted) setState(() {});
  }

  String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String money(dynamic v) {
    final n = v is num ? v : double.tryParse('$v') ?? 0;
    return '${n.round()} د.ع';
  }

  Future<void> load({bool silent = false}) async {
    if (!appPermissions.canViewGeneralStats) return;
    if (period == 'custom' &&
        (start == null || end == null || !start!.isBefore(end!))) {
      setState(() => error = 'اختر تاريخ بداية ونهاية صحيحين للفترة.');
      return;
    }
    final version = ++_loadVersion;
    if (!silent) setState(() => loading = true);
    try {
      final r = await ApiService.getStats(
        period: period == 'custom' ? 'custom_time' : period,
        startDate: start == null ? null : date(start!),
        endDate: end == null ? null : date(end!),
        startAt: period == 'custom' ? start?.toUtc().toIso8601String() : null,
        endAt: period == 'custom' ? end?.toUtc().toIso8601String() : null,
        hours: period == 'hours' ? hours : null,
      );
      if (mounted && version == _loadVersion)
        setState(() {
          error = null;
          data = r;
          loading = false;
        });
    } catch (_) {
      if (mounted && version == _loadVersion)
        setState(() {
          loading = false;
          error = ApiService.lastError;
        });
    }
  }

  Future<void> pick(bool isStart) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (start ?? DateTime.now())
          : (end ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      if (!mounted) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          (isStart ? start : end) ?? DateTime.now(),
        ),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (t == null || !mounted) return;
      final chosen = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      setState(() {
        if (isStart)
          start = chosen;
        else
          end = chosen;
      });
      if (start != null && end != null) load();
    }
  }

  Widget card(String title, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(.28)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textGray,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  Widget section(String title, Widget child, IconData icon) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.primaryLight),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget timeline() {
    final rows = List<Map<String, dynamic>>.from(data['timeline'] ?? const []);
    if (rows.isEmpty)
      return Text(
        'لا توجد بيانات ضمن هذه الفترة',
        style: TextStyle(color: AppColors.textGray),
      );
    final max = rows
        .map((r) => (r['revenue'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final visible = rows.length > 31 ? rows.sublist(rows.length - 31) : rows;
    return SizedBox(
      height: 230,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: visible.map((r) {
          final amount = (r['revenue'] as num?)?.toDouble() ?? 0;
          final h = max == 0 ? 4.0 : amount / max * 160 + 4;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message:
                    '${r['label']}\n${money(amount)}\nطلبات: ${r['orders'] ?? 0}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: h,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${r['label']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textGray, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget payments() {
    final map = Map<String, dynamic>.from(data['payment_methods'] ?? {});
    if (map.isEmpty)
      return Text(
        'لا توجد مدفوعات',
        style: TextStyle(color: AppColors.textGray),
      );
    return Column(
      children: map.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.key,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                money(v['amount']),
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${v['count'] ?? 0} طلب',
                style: TextStyle(color: AppColors.textGray),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void productDetails(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> sales,
  ) {
    if (!appPermissions.canViewGeneralStats) return;
    final name = '${product['product_name']}';
    final quantity = (product['quantity'] as num?)?.toDouble() ?? 0;
    final revenue = (product['total_revenue'] as num?)?.toDouble() ?? 0;
    final profit = (product['total_profit'] as num?)?.toDouble() ?? 0;
    final allRevenue =
        (data['stats']?['total_revenue'] as num?)?.toDouble() ?? 0;
    final productSales = sales
        .where(
          (sale) => List<Map<String, dynamic>>.from(
            sale['items'] ?? const [],
          ).any((item) => '${item['product_name']}' == name),
        )
        .toList();
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: Row(
            children: [
              Icon(Icons.inventory_2, color: AppColors.primaryLight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _detailBox(
                        'الكمية المباعة',
                        '${quantity % 1 == 0 ? quantity.round() : quantity}',
                        Icons.shopping_cart,
                        AppColors.primaryLight,
                      ),
                      _detailBox(
                        'إجمالي الإيراد',
                        money(revenue),
                        Icons.payments,
                        AppColors.success,
                      ),
                      if (appPermissions.canViewProfit)
                        _detailBox(
                          'إجمالي الربح',
                          money(profit),
                          Icons.trending_up,
                          AppColors.warning,
                        ),
                      _detailBox(
                        'عدد الطلبات',
                        '${productSales.length}',
                        Icons.receipt_long,
                        const Color(0xFFA855F7),
                      ),
                      _detailBox(
                        'متوسط سعر البيع',
                        money(quantity == 0 ? 0 : revenue / quantity),
                        Icons.sell,
                        Colors.teal,
                      ),
                      _detailBox(
                        'نسبة المبيعات',
                        '${allRevenue == 0 ? 0 : (revenue / allRevenue * 100).toStringAsFixed(1)}%',
                        Icons.percent,
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'الطلبات التي ظهر بها المنتج',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (productSales.isEmpty)
                    Text(
                      'لا توجد طلبات ضمن الفترة الحالية',
                      style: TextStyle(color: AppColors.textGray),
                    ),
                  ...productSales.map(
                    (sale) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.receipt_long,
                        color: AppColors.historyIcon,
                      ),
                      title: Text(
                        'طلب #${sale['id']} • ${sale['created_at']}',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        'الكاشير: ${sale['cashier_name']} • الدفع: ${sale['payment_method']}',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        color: AppColors.primaryLight,
                        onPressed: () {
                          Navigator.pop(context);
                          saleDetails(sale);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailBox(String title, String value, IconData icon, Color color) =>
      Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: AppColors.textGray, fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget topProducts(List<Map<String, dynamic>> sales) {
    final list = List<Map<String, dynamic>>.from(
      data['top_products'] ?? const [],
    );
    if (list.isEmpty)
      return Text(
        'لا توجد مبيعات أصناف',
        style: TextStyle(color: AppColors.textGray),
      );
    return Column(
      children: list.asMap().entries.map((e) {
        final p = e.value;
        return ListTile(
          onTap: () => productDetails(p, sales),
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: AppColors.primaryLight.withOpacity(.15),
            child: Text(
              '${e.key + 1}',
              style: TextStyle(color: AppColors.primaryLight),
            ),
          ),
          title: Text(
            '${p['product_name']}',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            'الكمية: ${p['quantity'] ?? 0} • اضغط لعرض التفاصيل الكاملة',
            style: TextStyle(color: AppColors.textGray),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                money(p['total_revenue']),
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left, color: AppColors.primaryLight),
            ],
          ),
        );
      }).toList(),
    );
  }

  void saleDetails(Map<String, dynamic> sale) {
    if (!appPermissions.canViewGeneralStats) return;
    final stats = Map<String, dynamic>.from(data['stats'] ?? {});
    showDialog(
      context: context,
      builder: (_) => SaleDetailsDialog(
        sale: sale,
        periodRevenue: (stats['total_revenue'] as num?)?.toDouble(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!appPermissions.canViewGeneralStats) {
      return const Center(child: Text('هذه الصفحة متاحة للإدارة فقط.'));
    }
    final compact = MediaQuery.sizeOf(context).width < 700;
    final stats = Map<String, dynamic>.from(data['stats'] ?? {});
    final sales = List<Map<String, dynamic>>.from(data['sales'] ?? const []);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: loading
            ? Center(
                child: CircularProgressIndicator(color: AppColors.primaryLight),
              )
            : RefreshIndicator(
                onRefresh: load,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error!,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                      Row(
                        children: [
                          Icon(
                            Icons.analytics_rounded,
                            color: AppColors.primaryLight,
                            size: 34,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'لوحة الإحصائيات والتقارير',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: load,
                            icon: Icon(
                              Icons.refresh,
                              color: AppColors.primaryLight,
                            ),
                          ),
                          ExportMenu(
                            path: '/api/reports/export',
                            label: 'تصدير الفترة المعروضة',
                            enabled:
                                !loading && error == null && data.isNotEmpty,
                            query: Map<String, dynamic>.from(
                              data['resolved_filter'] ?? {},
                            ).map((k, v) => MapEntry(k, '$v')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            Text(
                              'الفترة:',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            ...periods.entries.map(
                              (p) => ChoiceChip(
                                label: Text(p.value),
                                selected: period == p.key,
                                selectedColor: AppColors.primaryLight,
                                labelStyle: TextStyle(
                                  color: period == p.key
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    period = p.key;
                                    if (p.key != 'custom') {
                                      start = null;
                                      end = null;
                                    } else {
                                      final now = DateTime.now();
                                      start = DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                      );
                                      end = now;
                                    }
                                  });
                                  load();
                                },
                              ),
                            ),
                            for (final h in [1, 4, 6, 8, 12, 16])
                              ChoiceChip(
                                label: Text('آخر $h ساعة'),
                                selected: period == 'hours' && hours == h,
                                onSelected: (_) {
                                  setState(() {
                                    period = 'hours';
                                    hours = h.toDouble();
                                  });
                                  load();
                                },
                              ),
                            if (period == 'hours')
                              SizedBox(
                                width: 170,
                                child: TextFormField(
                                  key: ValueKey('hours-$hours'),
                                  initialValue: '$hours',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'آخر كم ساعة؟',
                                    helperText: 'Enter للتطبيق',
                                  ),
                                  onFieldSubmitted: (value) {
                                    final n = double.tryParse(value);
                                    if (n == null ||
                                        !n.isFinite ||
                                        n <= 0 ||
                                        n > 8760) {
                                      setState(
                                        () => error =
                                            'أدخل عدد ساعات أكبر من صفر وحتى 8760.',
                                      );
                                      return;
                                    }
                                    setState(() => hours = n);
                                    load();
                                  },
                                ),
                              ),
                            if (period == 'custom')
                              OutlinedButton.icon(
                                onPressed: () => pick(true),
                                icon: const Icon(Icons.date_range),
                                label: Text(
                                  start == null
                                      ? 'من تاريخ ووقت'
                                      : '${date(start!)} ${start!.hour.toString().padLeft(2, '0')}:${start!.minute.toString().padLeft(2, '0')}',
                                ),
                              ),
                            if (period == 'custom')
                              OutlinedButton.icon(
                                onPressed: () => pick(false),
                                icon: const Icon(Icons.event),
                                label: Text(
                                  end == null
                                      ? 'إلى تاريخ ووقت'
                                      : '${date(end!)} ${end!.hour.toString().padLeft(2, '0')}:${end!.minute.toString().padLeft(2, '0')}',
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${data['start_date'] ?? ''}  —  ${data['end_date'] ?? ''}',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      if (period == 'custom' || period == 'hours')
                        const Text(
                          'الوقت محلي. البداية مشمولة والنهاية غير مشمولة. التصدير يثبت الفترة الظاهرة عند تحميل النتائج.',
                        ),
                      const SizedBox(height: 16),
                      if (compact)
                        SectionTabs(
                          labels: const [
                            'الملخص',
                            'الرسوم والدفع',
                            'المنتجات والطلبات',
                          ],
                          selected: _mobileSection,
                          onSelected: (value) =>
                              setState(() => _mobileSection = value),
                        ),
                      if (!compact || _mobileSection == 0)
                        LayoutBuilder(
                          builder: (context, c) {
                            final cols = c.maxWidth > 1100
                                ? 4
                                : c.maxWidth > 700
                                ? 2
                                : 1;
                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: cols,
                              mainAxisExtent:
                                  140 +
                                  (MediaQuery.textScalerOf(context).scale(1) -
                                              1)
                                          .clamp(0, 2) *
                                      100,
                              crossAxisSpacing: 13,
                              mainAxisSpacing: 13,
                              children: [
                                card(
                                  'صافي الإيرادات',
                                  money(stats['total_revenue']),
                                  Icons.payments,
                                  AppColors.success,
                                ),
                                card(
                                  'الربح قبل المصاريف',
                                  money(stats['gross_profit']),
                                  Icons.trending_up,
                                  AppColors.primaryLight,
                                ),
                                card(
                                  'صافي الربح / الخسارة بعد المصاريف',
                                  money(stats['final_net_profit']),
                                  Icons.account_balance,
                                  AppColors.warning,
                                ),
                                card(
                                  'عدد الطلبات',
                                  '${stats['total_sales_count'] ?? 0}',
                                  Icons.receipt_long,
                                  const Color(0xFFA855F7),
                                ),
                                card(
                                  'متوسط الطلب',
                                  money(stats['average_order_value']),
                                  Icons.shopping_basket,
                                  Colors.teal,
                                ),
                                card(
                                  'هامش الربح',
                                  '${stats['profit_margin_pct'] ?? 0}%',
                                  Icons.percent,
                                  Colors.orange,
                                ),
                                card(
                                  'إجمالي الخصومات',
                                  money(stats['total_discount']),
                                  Icons.discount,
                                  AppColors.danger,
                                ),
                                card(
                                  'الأصناف المباعة',
                                  '${stats['total_items_sold'] ?? 0}',
                                  Icons.inventory_2,
                                  Colors.indigo,
                                ),
                                card(
                                  'إجمالي البيع قبل الخصومات',
                                  money(stats['gross_sales']),
                                  Icons.sell_outlined,
                                  AppColors.primaryLight,
                                ),
                                card(
                                  'كلفة شراء البضاعة المباعة',
                                  money(stats['total_cost']),
                                  Icons.inventory_outlined,
                                  Colors.indigo,
                                ),
                                card(
                                  'المصاريف التشغيلية',
                                  money(stats['total_expenses']),
                                  Icons.receipt_long_outlined,
                                  AppColors.danger,
                                ),
                                card(
                                  'شراء وتوريد المخزون',
                                  money(stats['total_supply']),
                                  Icons.local_shipping_outlined,
                                  Colors.teal,
                                ),
                                card(
                                  'المصاريف والتوريد معاً',
                                  money(stats['total_outflows']),
                                  Icons.payments_outlined,
                                  Colors.orange,
                                ),
                                card(
                                  'البيع ناقص المصاريف والتوريد',
                                  money(stats['sales_less_outflows']),
                                  Icons.swap_vert,
                                  Colors.blueGrey,
                                ),
                                card(
                                  'الربح الصافي الموجب',
                                  money(stats['profit']),
                                  Icons.trending_up,
                                  AppColors.success,
                                ),
                                card(
                                  'الخسارة',
                                  money(stats['loss']),
                                  Icons.trending_down,
                                  AppColors.danger,
                                ),
                                card(
                                  'الرواتب المدفوعة',
                                  money(stats['salary_expenses']),
                                  Icons.badge_outlined,
                                  Colors.indigo,
                                ),
                                card(
                                  'الإيجارات المدفوعة',
                                  money(stats['rent_expenses']),
                                  Icons.home_work_outlined,
                                  Colors.teal,
                                ),
                                card(
                                  'الاشتراكات المدفوعة',
                                  money(stats['subscription_expenses']),
                                  Icons.autorenew,
                                  AppColors.primaryLight,
                                ),
                                card(
                                  'الالتزامات الشهرية المدفوعة',
                                  money(stats['fixed_expenses']),
                                  Icons.event_repeat,
                                  Colors.orange,
                                ),
                              ],
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                      if (!compact || _mobileSection == 0)
                        section(
                          'تفاصيل المصاريف والحساب',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'الربح قبل المصاريف = صافي البيع − كلفة البضاعة المباعة. الربح بعد المصاريف = الربح قبل المصاريف − المصاريف التشغيلية. التوريد يظهر منفصلاً ولا يُخصم مرة ثانية من الربح.',
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'الرواتب والإيجارات والاشتراكات أجزاء من المصاريف؛ لا تجمعها معها مرة ثانية. الالتزامات المدفوعة قد تشمل الإيجار والاشتراكات. الرواتب والمسودات غير المصروفة لا تدخل المصاريف.',
                              ),
                              if ((data['legacy_inventory_expenses'] as num? ??
                                      0) >
                                  0)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'توجد سجلات توريد قديمة بالقيم المحفوظة سابقاً. راجع التوريد بالوزن القديم؛ تصحيح وحدة الوزن يطبق على العمليات الجديدة.',
                                    style: TextStyle(color: AppColors.warning),
                                  ),
                                ),
                              for (final e in Map<String, dynamic>.from(
                                data['expense_categories'] ?? {},
                              ).entries)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('${e.key}: ${money(e.value)}'),
                                ),
                            ],
                          ),
                          Icons.account_balance_wallet_outlined,
                        ),
                      const SizedBox(height: 16),
                      if (!compact || _mobileSection == 1)
                        LayoutBuilder(
                          builder: (context, c) {
                            final wide = c.maxWidth > 900;
                            final a = section(
                              'المبيعات عبر الزمن',
                              timeline(),
                              Icons.show_chart,
                            );
                            final b = section(
                              'طرق الدفع',
                              payments(),
                              Icons.account_balance_wallet,
                            );
                            return wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 2, child: a),
                                      const SizedBox(width: 15),
                                      Expanded(child: b),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      a,
                                      const SizedBox(height: 15),
                                      b,
                                    ],
                                  );
                          },
                        ),
                      const SizedBox(height: 16),
                      if (!compact || _mobileSection == 2)
                        LayoutBuilder(
                          builder: (context, c) {
                            final wide = c.maxWidth > 900;
                            final a = section(
                              'الأصناف الأكثر مبيعاً',
                              topProducts(sales),
                              Icons.star,
                            );
                            final b = section(
                              'آخر العمليات',
                              sales.isEmpty
                                  ? Text(
                                      'لا توجد مبيعات ضمن الفترة',
                                      style: TextStyle(
                                        color: AppColors.textGray,
                                      ),
                                    )
                                  : Column(
                                      children: sales
                                          .take(8)
                                          .map(
                                            (s) => ListTile(
                                              onTap: () => saleDetails(s),
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(
                                                Icons.receipt_long,
                                                color: AppColors.historyIcon,
                                              ),
                                              title: Text(
                                                'طلب #${s['id']} • ${money(s['total_selling_amount'])}',
                                                style: TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              subtitle: Text(
                                                '${s['created_at']} • ${s['cashier_name']}',
                                                style: TextStyle(
                                                  color: AppColors.textGray,
                                                ),
                                              ),
                                              trailing: const Icon(
                                                Icons.chevron_left,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                              Icons.receipt_long,
                            );
                            return wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: a),
                                      const SizedBox(width: 15),
                                      Expanded(child: b),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      a,
                                      const SizedBox(height: 15),
                                      b,
                                    ],
                                  );
                          },
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'الإحصائيات للطلبات المكتملة فقط؛ السلال وطلبات الطاولات المفتوحة لا تُحسب كمبيعات. تتحدث تلقائياً بعد البيع وعند فتح الصفحة وكل 30 ثانية أثناء عرضها.',
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    ApiService.reportsRevision.removeListener(_reportsChanged);
    ThemeService.themeModeNotifier.removeListener(themeChanged);
    super.dispose();
  }
}
