import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Add _customTotalSellingPrice inside _PosScreenState if not exists
if "double? _customTotalSellingPrice;" not in text:
    state_class_def = "class _PosScreenState extends State<PosScreen> {"
    idx = text.find(state_class_def)
    if idx != -1:
        insert_idx = text.find("{", idx) + 1
        text = text[:insert_idx] + "\n  double? _customTotalSellingPrice;" + text[insert_idx:]

# 2. Update _updateCartTotalDiscount
old_disc = """  void _updateCartTotalDiscount(double newTotalDiscount) {
    if (_cart.isEmpty) return;
    _globalDiscount = newTotalDiscount;
  }"""
new_disc = """  void _updateCartTotalDiscount(double newTotalDiscount) {
    if (_cart.isEmpty) return;
    final double itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    _globalDiscount = newTotalDiscount - itemDiscountSum;
  }"""
text = text.replace(old_disc, new_disc)

# 3. Update _updateCartFinalTotal
old_final = """  void _updateCartFinalTotal(double newFinalTotal) {
    if (_cart.isEmpty) return;
    final totalSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    
    // newFinalTotal = totalSellingSum - itemDiscountSum - globalDiscount
    // globalDiscount = totalSellingSum - itemDiscountSum - newFinalTotal
    double targetGlobalDiscount = totalSellingSum - itemDiscountSum - newFinalTotal;
    _updateCartTotalDiscount(targetGlobalDiscount);
  }"""
new_final = """  void _updateCartFinalTotal(double newFinalTotal) {
    if (_cart.isEmpty) return;
    final double baseSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final double totalSellingSum = _customTotalSellingPrice ?? baseSellingSum;
    final double itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    
    double targetGlobalDiscount = totalSellingSum - itemDiscountSum - newFinalTotal;
    _globalDiscount = targetGlobalDiscount;
  }"""
text = text.replace(old_final, new_final)

# 4. Modify buildCartArea to calculate totalSellingSum with _customTotalSellingPrice
# There is a line: final double totalSellingSum = cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
old_calc = "final double totalSellingSum = cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);"
new_calc = """final double baseSellingSum = cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final double totalSellingSum = _customTotalSellingPrice ?? baseSellingSum;"""
text = text.replace(old_calc, new_calc)

# 5. Modify onUpdateTotalSelling
old_on_up_sell = """                          onUpdateTotalSelling: (newTotal) {
                            if (totalSellingSum > 0) {
                              double ratio = newTotal / totalSellingSum;
                              setState(() {
                                for (var i in _cart) { i.unitSellingPrice *= ratio; }
                              });
                            }
                          },"""
new_on_up_sell = """                          onUpdateTotalSelling: (newTotal) {
                            setState(() {
                              _customTotalSellingPrice = newTotal;
                            });
                          },"""
text = text.replace(old_on_up_sell, new_on_up_sell)

# 6. Reset _customTotalSellingPrice when cart is cleared
old_clear = """  void _clearCart() {
    setState(() {
      _cart.clear();"""
new_clear = """  void _clearCart() {
    setState(() {
      _cart.clear();
      _customTotalSellingPrice = null;"""
text = text.replace(old_clear, new_clear)

# 7. Reset _customTotalSellingPrice when a new item is added? Let's keep it simple: 
# Only _clearCart resets it, or we can just leave it to the user.
# Wait, if they add a new item, the base sum changes, but the custom total remains.
# We probably should reset `_customTotalSellingPrice = null;` inside `_addToCart` to avoid weirdness.
old_add = """  void _addToCart(ProductModel product, {double qty = 1.0, double? customPrice}) {
    setState(() {"""
new_add = """  void _addToCart(ProductModel product, {double qty = 1.0, double? customPrice}) {
    setState(() {
      _customTotalSellingPrice = null;"""
text = text.replace(old_add, new_add)

old_remove = """  void _removeFromCart(int index) {
    setState(() {"""
new_remove = """  void _removeFromCart(int index) {
    setState(() {
      _customTotalSellingPrice = null;"""
text = text.replace(old_remove, new_remove)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Applied strict detachment fixes safely!")
