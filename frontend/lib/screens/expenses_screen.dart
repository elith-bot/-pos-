import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool _isLoading = true;
  List<dynamic> _expenses = [];
  double _totalAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getExpenses();
    if (mounted) {
      setState(() {
        _expenses = data['expenses'] ?? [];
        _totalAmount = (data['total_amount'] ?? 0.0).toDouble();
        _isLoading = false;
      });
    }
  }

  void _showAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final categoryCtrl = TextEditingController(text: 'عام');
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.request_quote, color: AppColors.danger),
            SizedBox(width: 8),
            Text('تسجيل مصروف جديد', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'عنوان المصروف (مثلاً: إيجار، كهرباء، رواتب)',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'المبلغ الإجمالي',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: categoryCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'التصنيف (قسم الصرفيات)',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'ملاحظات إضافية',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              final title = titleCtrl.text.trim();
              final amount = double.tryParse(amountCtrl.text) ?? 0.0;
              if (title.isNotEmpty && amount > 0) {
                Navigator.pop(ctx);
                await ApiService.addExpense(title, amount, categoryCtrl.text.trim(), notesCtrl.text.trim());
                _loadExpenses();
              }
            },
            child: const Text('حفظ المصروف', style: TextStyle(color: Colors.white)),
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
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Expenses Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.surface, Color(0xFF331B1B)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.stockLowBg.withOpacity(0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.account_balance_wallet, color: AppColors.danger, size: 32),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('إجمالي الصرفيات والمصاريف',
                                style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontMedium)),
                            const SizedBox(height: 4),
                            Text(
                              '${_totalAmount.toStringAsFixed(0)} د.ع',
                              style: const TextStyle(
                                  color: Color(0xFFFCA5A5), fontWeight: FontWeight.bold, fontSize: AppSizes.fontHuge),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('تسجيل مصروف جديد',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: _showAddExpenseDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Expenses Table List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.danger))
                    : _expenses.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.money_off, size: 64, color: Colors.white.withOpacity(0.2)),
                                const SizedBox(height: 10),
                                const Text('لا توجد مصاريف مسجلة حالياً', style: TextStyle(color: AppColors.textGray)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _expenses.length,
                            itemBuilder: (ctx, idx) {
                              final exp = _expenses[idx];
                              return Card(
                                color: AppColors.surface,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: AppColors.border),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.background,
                                    child: Text('#${exp['id']}',
                                        style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(exp['title'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader)),
                                  subtitle: Text(
                                    'التصنيف: ${exp['category']} • بواسطة: ${exp['created_by']} • ${exp['created_at']}',
                                    style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${exp['amount']} د.ع',
                                        style: const TextStyle(
                                            color: Color(0xFFFCA5A5), fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader),
                                      ),
                                      const SizedBox(width: 10),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: AppColors.danger, size: 20),
                                        onPressed: () async {
                                          await ApiService.deleteExpense(exp['id']);
                                          _loadExpenses();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
