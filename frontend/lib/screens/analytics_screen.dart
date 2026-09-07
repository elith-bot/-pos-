import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';
import '../core/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _sales = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getStats();
    final salesData = await ApiService.getSales();
    if (mounted) {
      setState(() {
        _stats = data;
        _sales = salesData;
        _isLoading = false;
      });
    }
  }

  void _showSaleDetails(Map<String, dynamic> sale) {
    showDialog(
      context: context,
      builder: (context) {
        final items = (sale['items'] as List?) ?? [];
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppColors.surface,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('تفاصيل الطلب #${sale['id']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الكاشير: ${sale['cashier_name']}', style: const TextStyle(color: Colors.white70)),
                        Text('التاريخ: ${sale['created_at']}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الإجمالي: ${sale['total_selling_amount']} د.ع', style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                        Text('الدفع: ${sale['payment_method']}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 30),
                    const Text('المنتجات:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader)),
                    const SizedBox(height: 10),
                    ...items.map((item) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text('${item['product_name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                Text('${item['quantity']}x', style: const TextStyle(color: Colors.white70)),
                                const SizedBox(width: 20),
                                Text('${item['total_price']} د.ع', style: const TextStyle(color: AppColors.historyIcon, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                if (appPermissions.canViewPurchasePrice)
                                  Text('شراء: ${item['unit_purchase_price']} د.ع', style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontSmall))
                                else
                                  const Text('شراء: ***', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontSmall)),
                                
                                if (appPermissions.canViewSellingPrice)
                                  Text('بيع: ${item['unit_selling_price']} د.ع', style: const TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontSmall)),

                                if (appPermissions.canViewDiscount)
                                  Text('خصم: ${item['discount']} د.ع', style: const TextStyle(color: AppColors.warning, fontSize: AppSizes.fontSmall)),
                                
                                if (appPermissions.canViewProfit)
                                  Text('ربح الصنف: ${item['profit']} د.ع', style: const TextStyle(color: AppColors.success, fontSize: AppSizes.fontSmall))
                                else
                                  const Text('ربح الصنف: ***', style: TextStyle(color: AppColors.success, fontSize: AppSizes.fontSmall)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontLarge, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(color: color, fontSize: AppSizes.fontHuge, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bar_chart_rounded, color: AppColors.primaryLight, size: 32),
                              SizedBox(width: 10),
                              Text('الإحصائيات والتقارير المالية',
                                  style: TextStyle(color: Colors.white, fontSize: AppSizes.fontHuge, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: AppColors.primaryLight),
                            onPressed: _loadStats,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Grid of KPI Stat Cards
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.1,
                        children: [
                          _buildStatCard(
                            title: 'عدد المبيعات الكلي',
                            value: '${_stats['total_sales_count'] ?? 0} عملية',
                            icon: Icons.receipt_long,
                            color: AppColors.primaryLight,
                            bgColor: const Color(0xFF0369A1).withOpacity(0.3),
                          ),
                          _buildStatCard(
                            title: 'إجمالي الإيرادات (المبيعات)',
                            value: '${_stats['total_revenue'] ?? 0} د.ع',
                            icon: Icons.attach_money,
                            color: AppColors.success,
                            bgColor: AppColors.stockHighBg.withOpacity(0.3),
                          ),
                          _buildStatCard(
                            title: 'أرباح المبيعات الإجمالية',
                            value: '${_stats['gross_profit'] ?? 0} د.ع',
                            icon: Icons.trending_up,
                            color: AppColors.historyIcon,
                            bgColor: const Color(0xFF065F46).withOpacity(0.3),
                          ),
                          _buildStatCard(
                            title: 'إجمالي الصرفيات والمصاريف',
                            value: '${_stats['total_expenses'] ?? 0} د.ع',
                            icon: Icons.money_off,
                            color: AppColors.danger,
                            bgColor: AppColors.stockLowBg.withOpacity(0.3),
                          ),
                          _buildStatCard(
                            title: 'صافي الأرباح النهائية (الربح - المصاريف)',
                            value: '${_stats['final_net_profit'] ?? 0} د.ع',
                            icon: Icons.account_balance,
                            color: AppColors.warning,
                            bgColor: const Color(0xFF78350F).withOpacity(0.3),
                          ),
                          _buildStatCard(
                            title: 'إجمالي أصناف المنتجات',
                            value: '${_stats['total_products'] ?? 0} منتج',
                            icon: Icons.inventory_2,
                            color: const Color(0xFFA855F7),
                            bgColor: const Color(0xFF581C87).withOpacity(0.3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Text('سجل المبيعات الأخير', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontHuge, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      if (_sales.isEmpty)
                        const Center(child: Text('لا يوجد سجل مبيعات حتى الآن.', style: TextStyle(color: Colors.white54, fontSize: AppSizes.fontHeader)))
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _sales.length,
                          itemBuilder: (context, index) {
                            final sale = _sales[index];
                            return Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withOpacity(0.05))),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: AppColors.historyIcon.withOpacity(0.2), shape: BoxShape.circle),
                                  child: const Icon(Icons.receipt_long, color: AppColors.historyIcon),
                                ),
                                title: Text('طلب #${sale['id']} - ${sale['total_selling_amount']} د.ع', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader)),
                                subtitle: Text('${sale['created_at']}  |  الكاشير: ${sale['cashier_name']}', style: const TextStyle(color: Colors.white54, fontSize: AppSizes.fontMedium)),
                                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                                onTap: () => _showSaleDetails(sale),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
