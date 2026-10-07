import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Add _customTotalSellingPrice to _PosScreenState
if "double? _customTotalSellingPrice;" not in text:
    state_start = text.find("class _PosScreenState extends State<PosScreen> {")
    if state_start != -1:
        insert_idx = text.find("double _globalDiscount = 0.0;", state_start)
        if insert_idx != -1:
            text = text[:insert_idx] + "double? _customTotalSellingPrice;\n  " + text[insert_idx:]

# 2. Update _updateCartTotalDiscount
old_discount_func = """  void _updateCartTotalDiscount(double newTotalDiscount) {
    if (_cart.isEmpty) return;
    _globalDiscount = newTotalDiscount;
  }"""
new_discount_func = """  void _updateCartTotalDiscount(double newTotalDiscount) {
    if (_cart.isEmpty) return;
    final itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    _globalDiscount = newTotalDiscount - itemDiscountSum;
  }"""
text = text.replace(old_discount_func, new_discount_func)

# 3. Update _updateCartFinalTotal
old_final_func_regex = r"  void _updateCartFinalTotal\(double newFinalTotal\) \{.*?_updateCartTotalDiscount\(targetGlobalDiscount\);\n  \}"
new_final_func = """  void _updateCartFinalTotal(double newFinalTotal) {
    if (_cart.isEmpty) return;
    final baseSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final totalSellingSum = _customTotalSellingPrice ?? baseSellingSum;
    final itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    
    double targetGlobalDiscount = totalSellingSum - itemDiscountSum - newFinalTotal;
    _globalDiscount = targetGlobalDiscount;
  }"""
text = re.sub(old_final_func_regex, new_final_func, text, flags=re.DOTALL)

# 4. In buildCartArea, update totalSellingSum
total_selling_calc = r"final double totalSellingSum = cart\.fold\(0\.0, \(sum, i\) => sum \+ i\.totalSellingAmount\);"
new_total_selling_calc = """final double baseSellingSum = cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
            final double totalSellingSum = _customTotalSellingPrice ?? baseSellingSum;"""
text = re.sub(total_selling_calc, new_total_selling_calc, text)

# 5. In FAB layout builder, update totalSellingSum too!
total_selling_calc_fab = r"final double totalSellingSum = cart\.fold\(0\.0, \(sum, i\) => sum \+ i\.totalSellingAmount\);"
# Note: we already replaced this with the above regex if it matches multiple times, let's just make sure.

# 6. In CartSummaryWidget invocation, update onUpdateTotalSelling
old_on_update_selling = """onUpdateTotalSelling: (newTotal) {
                            if (totalSellingSum > 0) {
                              double ratio = newTotal / totalSellingSum;
                              setState(() {
                                for (var i in _cart) { i.unitSellingPrice *= ratio; }
                              });
                            }
                          },"""
new_on_update_selling = """onUpdateTotalSelling: (newTotal) {
                            setState(() {
                              _customTotalSellingPrice = newTotal;
                            });
                          },"""
text = text.replace(old_on_update_selling, new_on_update_selling)

# 7. Add a reset of _customTotalSellingPrice and _globalDiscount when clearing cart or modifying cart items directly?
# The user wants them detached. So if cart is updated, maybe they remain? 
# Or maybe we just let them be, but we need to reset them in `_clearCart`.
clear_cart_str = """  void _clearCart() {
    setState(() {
      _cart.clear();
      _globalDiscount = 0.0;"""
new_clear_cart_str = """  void _clearCart() {
    setState(() {
      _cart.clear();
      _globalDiscount = 0.0;
      _customTotalSellingPrice = null;"""
text = text.replace(clear_cart_str, new_clear_cart_str)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Applied detachment fixes!")
