import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Inject total calculations into buildCartArea's ValueListenableBuilder
# Find buildCartArea
start = text.find("Widget buildCartArea() {")
if start != -1:
    builder_start = text.find("builder: (context, _cart, child) {", start)
    if builder_start != -1:
        insert_idx = builder_start + len("builder: (context, _cart, child) {")
        calcs = """
        final double totalCostSum = _cart.fold(0.0, (sum, i) => sum + i.totalPurchaseCost);
        final double totalSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
        final double itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
        final double totalDiscountSum = itemDiscountSum + _globalDiscount;
        final double totalFinalAmount = totalSellingSum - totalDiscountSum;
        final double totalNetProfitSum = totalFinalAmount - totalCostSum;
"""
        text = text[:insert_idx] + calcs + text[insert_idx:]

# 2. Update all setState loops inside the cart bottom summary that update cart to also trigger _cartNotifier
# Since they do things like: 
#   setState(() { for (var i in _cart) { i.unitSellingPrice *= ratio; } });
# We should change them to:
#   for (var i in _cart) { i.unitSellingPrice *= ratio; } 
#   _cartNotifier.value = List.from(_cart);
text = text.replace(
    "setState(() {\n                                      for (var i in _cart) { i.unitSellingPrice *= ratio; }\n                                    });",
    "for (var i in _cart) { i.unitSellingPrice *= ratio; }\n                                    _cartNotifier.value = List.from(_cart);"
)

text = text.replace(
    "setState(() {\n                                          for (var i in _cart) { i.unitSellingPrice *= ratio; }\n                                        });",
    "for (var i in _cart) { i.unitSellingPrice *= ratio; }\n                                          _cartNotifier.value = List.from(_cart);"
)

# 3. Fix the grid item controller bug
# The line is: final cardCtrl = _getController('card_qty_${product.id}', '$cardQty');
# We need to change it to properly sync text while allowing typing
grid_ctrl_logic = """                                        final String fQty = _formatQty(cardQty);
                                        final cardCtrl = _getController('card_qty_${product.id}', fQty);
                                        if (double.tryParse(cardCtrl.text) != cardQty && cardCtrl.text != fQty) {
                                          cardCtrl.text = fQty;
                                        }"""

text = text.replace(
    "final cardCtrl = _getController('card_qty_${product.id}', '$cardQty');",
    grid_ctrl_logic
)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Applied fixes to cart totals and grid items!")
