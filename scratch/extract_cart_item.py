import re      
 
file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Replace the inner builder logic
start_str = "final cartQtyCtrl = _getController('cart_qty_$pId', _formatQty(item.quantity));"
end_str = "                              return Card("
idx1 = text.find(start_str)

def find_closing_brace(s, start):
    count = 0
    for i in range(start, len(s)):
        if s[i] == '(':
            count += 1
        elif s[i] == ')':
            count -= 1
            if count == 0:
                return i
    return -1
        
idx2 = text.find("return Card(", idx1)
idx3 = find_closing_brace(text, text.find("(", idx2)) + 1 # end of return Card(...);

if idx1 != -1 and idx2 != -1:
    new_card = """                              return CartItemWidget(
                                item: item,
                                onUpdate: () {
                                  _cartNotifier.value = List.from(_cartNotifier.value);
                                  if (_activeTable != null) _debouncedSaveTableOrder();
                                },
                                onUpdateQuantity: _updateProductQuantity,
                              );"""
    
    # We replace from start_str up to the end of Card() with new_card
    # Wait, we need to include the line where it ends
    text = text[:idx1] + new_card + text[idx3+1:] # +1 for the semicolon

# 2. Append the StatefulWidget at the end of the file
cart_item_widget_code = """
class CartItemWidget extends StatefulWidget {
  final CartItemModel item;
  final VoidCallback onUpdate;
  final void Function(ProductModel, double) onUpdateQuantity;

  const CartItemWidget({
    Key? key,
    required this.item,
    required this.onUpdate,
    required this.onUpdateQuantity,
  }) : super(key: key);

  @override
  State<CartItemWidget> createState() => _CartItemWidgetState();
}

class _CartItemWidgetState extends State<CartItemWidget> {
  bool _isExpanded = false;

  late TextEditingController _qtyCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _totalCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    String qStr = widget.item.quantity == widget.item.quantity.toInt()
        ? widget.item.quantity.toInt().toString()
        : widget.item.quantity.toString();
    _qtyCtrl = TextEditingController(text: qStr);
    _discountCtrl = TextEditingController(text: widget.item.discount.toStringAsFixed(0));
    _totalCtrl = TextEditingController(text: widget.item.totalPrice.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(CartItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    String qStr = widget.item.quantity == widget.item.quantity.toInt()
        ? widget.item.quantity.toInt().toString()
        : widget.item.quantity.toString();
    if (_qtyCtrl.text != qStr) _qtyCtrl.text = qStr;

    String dStr = widget.item.discount.toStringAsFixed(0);
    if (_discountCtrl.text != dStr) _discountCtrl.text = dStr;

    String tStr = widget.item.totalPrice.toStringAsFixed(0);
    if (_totalCtrl.text != tStr) _totalCtrl.text = tStr;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _discountCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.background,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item Name & Delete Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.item.product.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                  onPressed: () => widget.onUpdateQuantity(widget.item.product, 0),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 1. Quantity Field
            Row(
              children: [
                const SizedBox(width: 80, child: Text('الكمية/الوزن:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal))),
                IconButton(
                  icon: const Icon(Icons.remove_circle, color: AppColors.danger, size: 20),
                  onPressed: () => widget.onUpdateQuantity(widget.item.product, widget.item.quantity - (widget.item.product.isWeight ? widget.item.product.weightIncrementStep : 1.0)),
                ),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: EdgeInsets.symmetric(vertical: 2),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final q = double.tryParse(val) ?? 0;
                        widget.onUpdateQuantity(widget.item.product, q);
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.success, size: 20),
                  onPressed: () => widget.onUpdateQuantity(widget.item.product, widget.item.quantity + (widget.item.product.isWeight ? widget.item.product.weightIncrementStep : 1.0)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Total Price Text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('السعر الكلي:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                Text(
                  '${widget.item.totalPrice.toStringAsFixed(0)} د.ع',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                ),
              ],
            ),
            
            // Discount Text (if any)
            if (widget.item.discount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الخصم:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal)),
                    Text(
                      '-${widget.item.discount.toStringAsFixed(0)} د.ع',
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
              // Discount Field Editable
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('خصم المنتج:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal))),
                  IconButton(
                    icon: const Icon(Icons.remove, color: AppColors.warning, size: 18),
                    onPressed: () {
                      widget.item.discount -= 100;
                      widget.onUpdate();
                    },
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _discountCtrl,
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
                          final d = double.tryParse(val) ?? 0;
                          widget.item.discount = d;
                          widget.onUpdate();
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.warning, size: 18),
                    onPressed: () {
                      widget.item.discount += 100;
                      widget.onUpdate();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Total Price Editable
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('السعر النهائي:', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                    onPressed: () {
                      widget.item.totalPrice = (widget.item.totalPrice - 250).clamp(0, 9999999);
                      widget.onUpdate();
                    },
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _totalCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final t = double.tryParse(val);
                          if (t != null) {
                            widget.item.totalPrice = t;
                            widget.onUpdate();
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    onPressed: () {
                      widget.item.totalPrice += 250;
                      widget.onUpdate();
                    },
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}
"""

text = text + cart_item_widget_code

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Cart Item extracted successfully!")
