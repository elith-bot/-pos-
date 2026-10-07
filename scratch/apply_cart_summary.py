import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Insert the CartSummaryWidget at the bottom of the file
cart_summary_widget = """
class CartSummaryWidget extends StatefulWidget {
  final double totalCostSum;
  final double totalSellingSum;
  final double totalDiscountSum;
  final double totalFinalAmount;
  final double totalNetProfitSum;
  final int totalItems;
  final bool canViewPurchasePrice;
  final bool canViewProfit;
  final Function(double) onUpdateTotalSelling;
  final Function(double) onUpdateTotalDiscount;
  final Function(double) onUpdateFinalTotal;

  const CartSummaryWidget({
    Key? key,
    required this.totalCostSum,
    required this.totalSellingSum,
    required this.totalDiscountSum,
    required this.totalFinalAmount,
    required this.totalNetProfitSum,
    required this.totalItems,
    required this.canViewPurchasePrice,
    required this.canViewProfit,
    required this.onUpdateTotalSelling,
    required this.onUpdateTotalDiscount,
    required this.onUpdateFinalTotal,
  }) : super(key: key);

  @override
  _CartSummaryWidgetState createState() => _CartSummaryWidgetState();
}

class _CartSummaryWidgetState extends State<CartSummaryWidget> {
  late TextEditingController _sumSellCtrl;
  late TextEditingController _sumDiscCtrl;
  late TextEditingController _sumFinalCtrl;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _sumSellCtrl = TextEditingController(text: widget.totalSellingSum.toStringAsFixed(0));
    _sumDiscCtrl = TextEditingController(text: widget.totalDiscountSum.toStringAsFixed(0));
    _sumFinalCtrl = TextEditingController(text: widget.totalFinalAmount.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(CartSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    String ss = widget.totalSellingSum.toStringAsFixed(0);
    if (_sumSellCtrl.text != ss) _sumSellCtrl.text = ss;

    String sd = widget.totalDiscountSum.toStringAsFixed(0);
    if (_sumDiscCtrl.text != sd) _sumDiscCtrl.text = sd;

    String sf = widget.totalFinalAmount.toStringAsFixed(0);
    if (_sumFinalCtrl.text != sf) _sumFinalCtrl.text = sf;
  }

  @override
  void dispose() {
    _sumSellCtrl.dispose();
    _sumDiscCtrl.dispose();
    _sumFinalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.background,
      margin: const EdgeInsets.only(top: 8, bottom: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'المجموع الكلي للطلب',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                  ),
                ),
                Text(
                  '(${widget.totalItems} منتجات)',
                  style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Total Selling Display
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('السعر الكلي:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                Text(
                  '${widget.totalSellingSum.toStringAsFixed(0)} د.ع',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                ),
              ],
            ),

            if (widget.totalDiscountSum > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الخصم الكلي:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal)),
                    Text(
                      '-${widget.totalDiscountSum.toStringAsFixed(0)} د.ع',
                      style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                    ),
                  ],
                ),
              ),
            
            const Divider(color: Colors.white12, height: 24),
            
            // Show Details Button
            Center(
              child: TextButton.icon(
                icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.primaryLight, size: 20),
                label: Text(_isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل', style: const TextStyle(color: AppColors.primaryLight)),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 12),
              
              if (widget.canViewPurchasePrice) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مجموع سعر الشراء:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                    Text('${widget.totalCostSum.toStringAsFixed(0)} (ثابتة)', style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal)),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Edit Total Selling
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('سعر البيع الكلي:', style: TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontNormal))),
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: AppColors.primaryLight, size: 20),
                    onPressed: () => widget.onUpdateTotalSelling(widget.totalSellingSum - 500),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumSellCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final f = double.tryParse(val);
                          if (f != null) widget.onUpdateTotalSelling(f);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.primaryLight, size: 20),
                    onPressed: () => widget.onUpdateTotalSelling(widget.totalSellingSum + 500),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Edit Total Discount
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('الخصم الكلي:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal))),
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: AppColors.warning, size: 20),
                    onPressed: () => widget.onUpdateTotalDiscount(widget.totalDiscountSum - 250),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumDiscCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final d = double.tryParse(val);
                          if (d != null) widget.onUpdateTotalDiscount(d);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.warning, size: 20),
                    onPressed: () => widget.onUpdateTotalDiscount(widget.totalDiscountSum + 250),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Edit Final Amount
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('السعر النهائي:', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.white, size: 20),
                    onPressed: () => widget.onUpdateFinalTotal((widget.totalFinalAmount - 250).clamp(0, 9999999)),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumFinalCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontLarge, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final f = double.tryParse(val);
                          if (f != null) widget.onUpdateFinalTotal(f);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.white, size: 20),
                    onPressed: () => widget.onUpdateFinalTotal((widget.totalFinalAmount + 250).clamp(0, 9999999)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              if (widget.canViewProfit) ...[
                const Divider(color: Colors.white12, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مجموع صافي الربح:', style: TextStyle(color: AppColors.success, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold)),
                    Text('${widget.totalNetProfitSum.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                  ],
                ),
              ],
            ]
          ]
        )
      )
    );
  }
}
"""

if "class CartSummaryWidget" not in text:
    text += "\n" + cart_summary_widget

# 2. Replace the BOTTOM SUMMARY PANEL block with CartSummaryWidget instance
start_summary = text.find("// BOTTOM SUMMARY PANEL")
if start_summary != -1:
    # Find the end of the summary panel
    # We look for `// Checkout Button (Fixed)` or the end of the `Container` block.
    end_summary = text.find("// Checkout Button (Fixed)", start_summary)
    
    if end_summary != -1:
        replacement = """// BOTTOM SUMMARY PANEL WITH FULLY EDITABLE INTERACTIVE TOTALS & FOCUS RETENTION
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: CartSummaryWidget(
                        totalCostSum: totalCostSum,
                        totalSellingSum: totalSellingSum,
                        totalDiscountSum: totalDiscountSum,
                        totalFinalAmount: totalFinalAmount,
                        totalNetProfitSum: totalNetProfitSum,
                        totalItems: _cart.length,
                        canViewPurchasePrice: appPermissions.canViewPurchasePrice,
                        canViewProfit: appPermissions.canViewProfit,
                        onUpdateTotalSelling: (newTotal) {
                          if (totalSellingSum > 0) {
                            double ratio = newTotal / totalSellingSum;
                            for (var i in _cart) { i.unitSellingPrice *= ratio; }
                            _cartNotifier.value = List.from(_cart);
                          }
                        },
                        onUpdateTotalDiscount: (newDisc) {
                          _updateCartTotalDiscount(newDisc);
                        },
                        onUpdateFinalTotal: (newFinal) {
                          _updateCartFinalTotal(newFinal);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    """
        text = text[:start_summary] + replacement + text[end_summary:]

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Applied CartSummaryWidget fix!")
