import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/permissions_service.dart';
import 'export_menu.dart';

/// A historical receipt uses the amounts recorded at checkout, never current prices.
class SaleDetailsDialog extends StatelessWidget {
  const SaleDetailsDialog({super.key, required this.sale, this.periodRevenue});
  final Map<String, dynamic> sale;
  final double? periodRevenue;

  double? _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value');
  String _format(num value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  String _money(dynamic value) {
    final n = _number(value);
    return n == null ? 'غير مسجل' : '${_format(n)} د.ع';
  }

  String _percent(double? value, double? base) =>
      value == null || base == null || base == 0
      ? '—'
      : '${(value / base * 100).toStringAsFixed(1)}%';

  Widget _metrics(List<(String, String)> entries) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 650
          ? 3
          : constraints.maxWidth >= 420
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final entry in entries)
            Container(
              width: width,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.$1,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.$2,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      title,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!appPermissions.isActive) {
      return const AlertDialog(content: Text('ليس لديك صلاحية لعرض الطلب.'));
    }
    final items = List<Map<String, dynamic>>.from(sale['items'] ?? []);
    final gross = _number(sale['total_selling_amount']);
    final discount = _number(sale['total_discount']);
    final net = gross != null && discount != null ? gross - discount : null;
    final cost = _number(sale['total_purchase_cost']);
    final profit = _number(sale['net_profit']);
    final distinct = items
        .map((i) => i['product_id'] ?? i['product_name'])
        .toSet()
        .length;
    final pieces = items
        .where((i) => i['is_weight'] == false)
        .fold(0.0, (sum, i) => sum + (_number(i['quantity']) ?? 0));
    final grams = items
        .where((i) => i['is_weight'] == true)
        .fold(0.0, (sum, i) => sum + (_number(i['quantity']) ?? 0));
    final legacy = items.any((i) => i['is_weight'] == null);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 880,
          height: MediaQuery.sizeOf(context).height * .9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'تفاصيل الطلب #${sale['id']}',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق تفاصيل الطلب',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    if (sale['id'] is int)
                      ExportMenu(
                        path: '/api/sales/${sale['id']}/export',
                        label: 'تصدير تفاصيل الطلب',
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  key: const ValueKey('receipt-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _heading('بيانات الطلب'),
                    _metrics([
                      ('التاريخ والوقت', '${sale['created_at'] ?? 'غير مسجل'}'),
                      ('الكاشير', '${sale['cashier_name'] ?? 'غير مسجل'}'),
                      (
                        'طريقة الدفع',
                        '${sale['payment_method'] ?? 'غير مسجل'}',
                      ),
                      (
                        'نوع الطلب',
                        switch (sale['order_type']) {
                          'table' => 'طلب طاولة',
                          'direct' => 'بيع مباشر',
                          _ => 'غير مسجل',
                        },
                      ),
                      if (sale['table_name'] != null)
                        ('الطاولة', '${sale['table_name']}'),
                      ('عدد الأصناف المختلفة', '$distinct'),
                      ('عدد سطور الطلب', '${items.length}'),
                      if (items.any((i) => i['is_weight'] == false))
                        ('الكمية بالقطعة', _format(pieces)),
                      if (items.any((i) => i['is_weight'] == true))
                        ('الوزن المباع', '${_format(grams)} غم'),
                    ]),
                    _heading('مجاميع وإحصائيات الطلب'),
                    _metrics([
                      ('إجمالي البيع قبل الخصم', _money(gross)),
                      if (appPermissions.canViewDiscount)
                        (
                          discount != null && discount < 0
                              ? 'إجمالي الزيادة'
                              : 'إجمالي الخصومات',
                          _money(discount?.abs()),
                        ),
                      ('صافي الإيراد / النهائي', _money(net)),
                      if (appPermissions.canViewPurchasePrice)
                        ('إجمالي تكلفة الشراء', _money(cost)),
                      if (appPermissions.canViewProfit) ...[
                        ('ربح الطلب', _money(profit)),
                        ('هامش الربح', _percent(profit, net)),
                      ],
                      if (appPermissions.canViewDiscount)
                        ('نسبة الخصم من البيع', _percent(discount, gross)),
                      (
                        'متوسط الإيراد لكل صنف',
                        _money(
                          net != null && distinct > 0 ? net / distinct : null,
                        ),
                      ),
                      if (periodRevenue != null)
                        (
                          'مساهمة الطلب بمبيعات الفترة',
                          _percent(net, periodRevenue),
                        ),
                    ]),
                    if (appPermissions.canViewProfit)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'ربح الطلب بعد الخصومات وتكلفة الشراء، وقبل المصاريف العامة.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (legacy)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'بعض الطلبات القديمة لا تحتوي على وحدة كمية محفوظة؛ تظهر كمياتها كما سُجلت بدون افتراض قطعة أو وزن.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    _heading('تفاصيل جميع الأصناف'),
                    if (items.isEmpty)
                      const Text('لا توجد أصناف محفوظة لهذا الطلب.'),
                    for (var index = 0; index < items.length; index++)
                      _item(items[index], index, net),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'المبلغ النهائي',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _money(net),
                      key: const ValueKey('receipt-net'),
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(Map<String, dynamic> item, int index, double? orderNet) {
    final weighted = item['is_weight'] == true;
    final unit = weighted
        ? ' / ${item['weight_unit_grams']} غم'
        : item['is_weight'] == false
        ? ' / قطعة'
        : '';
    final net = _number(item['total_price']);
    final profit = _number(item['profit']);
    final price = _number(item['unit_selling_price']);
    final discount = _number(item['discount']);
    return Container(
      key: ValueKey('receipt-item-$index'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}. ${item['product_name']}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _metrics([
            (
              weighted ? 'الوزن' : 'الكمية المسجلة',
              '${_format(_number(item['quantity']) ?? 0)}${weighted
                  ? ' غم'
                  : item['is_weight'] == false
                  ? ' قطعة'
                  : ''}',
            ),
            ('سعر بيع الوحدة$unit', _money(price)),
            if (appPermissions.canViewPurchasePrice)
              ('سعر شراء الوحدة$unit', _money(item['unit_purchase_price'])),
            ('إجمالي البيع قبل الخصم', _money(item['gross_amount'])),
            if (appPermissions.canViewDiscount) ...[
              ('خصم وحدة التسعير$unit', _money(discount)),
              ('إجمالي خصم الصنف', _money(item['discount_amount'])),
            ],
            (
              'صافي سعر وحدة التسعير$unit',
              _money(
                price != null && discount != null ? price - discount : null,
              ),
            ),
            ('صافي إيراد الصنف', _money(net)),
            if (appPermissions.canViewPurchasePrice)
              (
                'تكلفة شراء الصنف',
                _money(
                  item['total_purchase_cost'] ??
                      (net != null && profit != null ? net - profit : null),
                ),
              ),
            if (appPermissions.canViewProfit) ...[
              ('ربح الصنف', _money(profit)),
              ('هامش ربح الصنف', _percent(profit, net)),
            ],
            ('مساهمة الصنف في الطلب', _percent(net, orderNet)),
          ]),
          const SizedBox(height: 8),
          Text(
            'خصم الصنف يشمل حصته من خصم الطلب عند تسجيله.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
