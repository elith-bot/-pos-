import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Update variable declarations
text = text.replace("List<CartItemModel> _cart = [];", "final ValueNotifier<List<CartItemModel>> _cartNotifier = ValueNotifier([]);\n  List<CartItemModel> get _cart => _cartNotifier.value;")
text = text.replace("final Map<int, double> _cardQuantities = {};", "final ValueNotifier<Map<int, double>> _cardQuantitiesNotifier = ValueNotifier({});\n  Map<int, double> get _cardQuantities => _cardQuantitiesNotifier.value;")
text = text.replace("double _globalDiscount = 0.0;", "final ValueNotifier<double> _globalDiscountNotifier = ValueNotifier(0.0);\n  double get _globalDiscount => _globalDiscountNotifier.value;\n  set _globalDiscount(double val) => _globalDiscountNotifier.value = val;")

# 2. Update _cart mutations to notify listeners
# Find _cart.add(...)
text = re.sub(r'_cart\.add\((.*?)\);', r'_cartNotifier.value = List.from(_cartNotifier.value)..add(\1);', text, flags=re.DOTALL)
# Find _cart.removeAt(...)
text = re.sub(r'_cart\.removeAt\((.*?)\);', r'_cartNotifier.value = List.from(_cartNotifier.value)..removeAt(\1);', text)
# Find _cart.clear()
text = text.replace("_cart.clear();", "_cartNotifier.value = [];")

# 3. Update _cardQuantities mutations to notify listeners
text = re.sub(r'_cardQuantities\[(.*?)\] = (.*?);', r'_cardQuantitiesNotifier.value = Map.from(_cardQuantitiesNotifier.value)..[ \1 ] = \2;', text)
text = text.replace("_cardQuantities.clear();", "_cardQuantitiesNotifier.value = {};")

# 4. Remove unnecessary setState from _updateProductQuantity
# Wait, _updateProductQuantity calls setState(() { ... });
# We should remove setState from _updateProductQuantity to avoid rebuilding the whole UI.
update_qty_orig = """  void _updateProductQuantity(ProductModel product, double newQty) {
    if (newQty < 0) newQty = 0.0;

    setState(() {
"""
update_qty_new = """  void _updateProductQuantity(ProductModel product, double newQty) {
    if (newQty < 0) newQty = 0.0;

    // No setState needed, Notifiers will handle it
"""
text = text.replace(update_qty_orig, update_qty_new)

# Find the end of setState in _updateProductQuantity
# It's at the end of the method before the _controllers part
end_setstate_orig = """      if (_cart.isEmpty) {
        _globalDiscount = 0.0;
      }
    });

    // Update card controller text if needed"""
end_setstate_new = """      if (_cart.isEmpty) {
        _globalDiscount = 0.0;
      }

    // Update card controller text if needed"""
text = text.replace(end_setstate_orig, end_setstate_new)

# 5. Remove setState from _updateCartTotalDiscount
text = text.replace("setState(() {\n      _globalDiscount = newTotalDiscount; // Allow negative values\n    });", "_globalDiscount = newTotalDiscount;")

# 6. Make buildCartArea reactive
build_cart_area_orig = "Widget buildCartArea() {\n    return Container("
build_cart_area_new = "Widget buildCartArea() {\n    return ValueListenableBuilder<List<CartItemModel>>(valueListenable: _cartNotifier, builder: (context, _cartValue, child) {\n      return Container("
text = text.replace(build_cart_area_orig, build_cart_area_new)
# Close the ValueListenableBuilder at the end of buildCartArea
# buildCartArea ends around line 1968 with:
#             ],
#           ),
#         );
# }
end_cart_area_orig = """            ],
          ),
        );
  }"""
end_cart_area_new = """            ],
          ),
        );
    });
  }"""
text = text.replace(end_cart_area_orig, end_cart_area_new)

# 7. Make the Product Card reactive
# Inside _products.isEmpty ? ... : GridView.builder
# We wrap the card in ValueListenableBuilder
grid_item_orig = """                                  itemBuilder: (context, index) {
                                    final product = _products[index];
                                    final cardQty = _cardQuantities[product.id] ?? 0.0;
"""
grid_item_new = """                                  itemBuilder: (context, index) {
                                    final product = _products[index];
                                    return ValueListenableBuilder<Map<int, double>>(
                                      valueListenable: _cardQuantitiesNotifier,
                                      builder: (context, quantities, child) {
                                        final cardQty = quantities[product.id] ?? 0.0;
"""
text = text.replace(grid_item_orig, grid_item_new)
# Close the ValueListenableBuilder inside GridView.builder
# The itemBuilder returns InkWell(...);
# So we need to add }); at the end of itemBuilder
grid_item_end_orig = """                                    );
                                  },
                                ),
"""
grid_item_end_new = """                                    );
                                      },
                                    );
                                  },
                                ),
"""
text = text.replace(grid_item_end_orig, grid_item_end_new)


# 8. Redesign Cart UI as requested
# We need to replace the Card inside ListView.builder in buildCartArea
old_card_start = "return Card("
old_card_end = "                                        // 4. Discount"
# Wait, replacing the huge block with regex is hard. Let's just create a completely new file or manually patch.

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Perf patch applied")
