import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool loading = true;
  String period = 'today';
  DateTime? start, end;
  Map<String, dynamic> data = {};
  final periods = const {
    'today': 'اليوم',
    'yesterday': 'أمس',
    'week': 'آخر 7 أيام',
    'month': 'هذا الشهر',
    'year': 'هذه السنة',
    'all': 'كل الفترات',
    'custom': 'مخصصة',
  };

  @override
  void initState() {
    super.initState();
    ThemeService.themeModeNotifier.addListener(themeChanged);
    load();
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

  Future<void> load() async {
    setState(() => loading = true);
    final r = await ApiService.getStats(
      period: period,
      startDate: start == null ? null : date(start!),
      endDate: end == null ? null : date(end!),
    );
    if (mounted)
      setState(() {
        data = r;
        loading = false;
      });
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
      setState(() {
        if (isStart)
          start = d;
        else
          end = d;
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
            Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
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

  Widget topProducts() {
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
            'الكمية: ${p['quantity'] ?? 0}',
            style: TextStyle(color: AppColors.textGray),
          ),
          trailing: Text(
            money(p['total_revenue']),
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }

  void saleDetails(Map<String, dynamic> s) {
    final items = List<Map<String, dynamic>>.from(s['items'] ?? const []);
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'تفاصيل الطلب #${s['id']}',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s['created_at']} • ${s['cashier_name']}',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                  const Divider(),
                  ...items.map(
                    (i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${i['product_name']}',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        'الكمية: ${i['quantity']}',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                      trailing: Text(
                        money(i['total_price']),
                        style: TextStyle(color: AppColors.primaryLight),
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

  @override
  Widget build(BuildContext context) {
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
                                    }
                                  });
                                  if (p.key != 'custom') load();
                                },
                              ),
                            ),
                            if (period == 'custom')
                              OutlinedButton.icon(
                                onPressed: () => pick(true),
                                icon: const Icon(Icons.date_range),
                                label: Text(
                                  start == null ? 'من تاريخ' : date(start!),
                                ),
                              ),
                            if (period == 'custom')
                              OutlinedButton.icon(
                                onPressed: () => pick(false),
                                icon: const Icon(Icons.event),
                                label: Text(
                                  end == null ? 'إلى تاريخ' : date(end!),
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
                      const SizedBox(height: 16),
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
                            childAspectRatio: c.maxWidth > 700 ? 2.5 : 3.5,
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
                                'أرباح المبيعات',
                                money(stats['gross_profit']),
                                Icons.trending_up,
                                AppColors.primaryLight,
                              ),
                              card(
                                'صافي الربح بعد المصاريف',
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
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 2, child: a),
                                    const SizedBox(width: 15),
                                    Expanded(child: b),
                                  ],
                                )
                              : Column(
                                  children: [a, const SizedBox(height: 15), b],
                                );
                        },
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, c) {
                          final wide = c.maxWidth > 900;
                          final a = section(
                            'الأصناف الأكثر مبيعاً',
                            topProducts(),
                            Icons.star,
                          );
                          final b = section(
                            'آخر العمليات',
                            sales.isEmpty
                                ? Text(
                                    'لا توجد مبيعات ضمن الفترة',
                                    style: TextStyle(color: AppColors.textGray),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: a),
                                    const SizedBox(width: 15),
                                    Expanded(child: b),
                                  ],
                                )
                              : Column(
                                  children: [a, const SizedBox(height: 15), b],
                                );
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'التقارير تعتمد على التوقيت المحلي وتُحدّث عند السحب للأسفل أو الضغط على تحديث.',
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
    ThemeService.themeModeNotifier.removeListener(themeChanged);
    super.dispose();
  }
}
