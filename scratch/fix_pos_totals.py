import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Fix the floatingActionButton to use ValueListenableBuilder
fab_start = text.find("floatingActionButton: LayoutBuilder(")
if fab_start != -1:
    fab_extended_start = text.find("return FloatingActionButton.extended(", fab_start)
    if fab_extended_start != -1:
        # Find where the extended finishes
        # Replace the return with the ValueListenableBuilder
        new_fab = """return ValueListenableBuilder<List<CartItemModel>>(
            valueListenable: _cartNotifier,
            builder: (context, cart, _) {
              final double totalSellingSum = cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
              final double itemDiscountSum = cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
              final double totalDiscountSum = itemDiscountSum + _globalDiscount;
              final double totalFinalAmount = totalSellingSum - totalDiscountSum;
              return FloatingActionButton.extended(
                backgroundColor: AppColors.primarySolid,
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: FractionallySizedBox(
                        heightFactor: 0.9,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          child: buildCartArea(),
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                label: Text('${cart.length} منتجات - ${totalFinalAmount.toStringAsFixed(0)} د.ع', 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              );
            }
          );"""
        
        # replace the old return FloatingActionButton.extended block
        fab_end = text.find(");", text.find("label: Text", fab_extended_start)) + 2
        text = text[:fab_extended_start] + new_fab + text[fab_end:]


# 2. Fix the Cart Item Details - Add Total Discount Field
cart_item_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"
# Wait, the CartItemWidget is already in pos_screen.dart
# I will find the Discount Field Editable and insert the Total Discount field before Total Price

# Let's use a targeted replace for CartItemWidget
cart_item_start = text.find("class CartItemWidget extends StatefulWidget")

# We want to add Total Discount logic. But in CartItemWidget, it's modifying widget.item.discount.
# If they edit Total Discount, they modify totalDiscountAmount, which means discount = newTotalDiscount / effectiveQuantity.
# If we add a field for it:
#     late TextEditingController _totalDiscountCtrl;
text = text.replace(
    "late TextEditingController _totalCtrl;", 
    "late TextEditingController _totalCtrl;\n  late TextEditingController _totalDiscountCtrl;"
)

text = text.replace(
    "_totalCtrl = TextEditingController(text: widget.item.totalPrice.toStringAsFixed(0));",
    "_totalCtrl = TextEditingController(text: widget.item.totalPrice.toStringAsFixed(0));\n    _totalDiscountCtrl = TextEditingController(text: widget.item.totalDiscountAmount.toStringAsFixed(0));"
)

text = text.replace(
    "if (_totalCtrl.text != tStr) _totalCtrl.text = tStr;",
    "if (_totalCtrl.text != tStr) _totalCtrl.text = tStr;\n\n    String tdStr = widget.item.totalDiscountAmount.toStringAsFixed(0);\n    if (_totalDiscountCtrl.text != tdStr) _totalDiscountCtrl.text = tdStr;"
)

text = text.replace(
    "_totalCtrl.dispose();",
    "_totalCtrl.dispose();\n    _totalDiscountCtrl.dispose();"
)

new_total_discount_ui = """              // Total Discount Field Editable
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('الخصم الكلي:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.remove, color: AppColors.warning, size: 18),
                    onPressed: () {
                      double currentTotalDiscount = widget.item.totalDiscountAmount;
                      double newTotalDiscount = (currentTotalDiscount - 250).clamp(0, widget.item.totalSellingAmount);
                      if (widget.item.effectiveQuantity > 0) {
                        widget.item.discount = newTotalDiscount / widget.item.effectiveQuantity;
                      }
                      widget.onUpdate();
                    },
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _totalDiscountCtrl,
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
                          if (d != null && widget.item.effectiveQuantity > 0) {
                            widget.item.discount = d / widget.item.effectiveQuantity;
                            widget.onUpdate();
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.warning, size: 18),
                    onPressed: () {
                      double currentTotalDiscount = widget.item.totalDiscountAmount;
                      double newTotalDiscount = currentTotalDiscount + 250;
                      if (widget.item.effectiveQuantity > 0) {
                        widget.item.discount = newTotalDiscount / widget.item.effectiveQuantity;
                      }
                      widget.onUpdate();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Total Price Editable"""

text = text.replace("// Total Price Editable", new_total_discount_ui)

# 3. Wrap GridView item in ValueListenableBuilder
grid_start = text.find("final cardQty = _cardQuantities[product.id] ?? 0;")
if grid_start != -1:
    # the line is "final cardQty = _cardQuantities[product.id] ?? 0;"
    # we want to replace from here until the "return Container(" with a ValueListenableBuilder
    
    start_replace = text.find("final cardQty", text.find("itemBuilder: (context, index) {"))
    end_replace = text.find("return Container(", start_replace)
    
    if start_replace != -1 and end_replace != -1:
        new_builder = """return ValueListenableBuilder<Map<int, double>>(
                                      valueListenable: _cardQuantitiesNotifier,
                                      builder: (context, cardQuantities, child) {
                                        final cardQty = cardQuantities[product.id] ?? 0;
                                        final cardCtrl = _getController('card_qty_${product.id}', '$cardQty');
                                        return Container("""
        
        # We also need to add the closing "});" at the end of the container
        # Let's find the end of the container.
        container_start = text.find("child: Column(", end_replace)
        container_end = text.find(");", text.find("          ),", container_start))
        
        # Actually it's easier to just use regex or find to add "});" where the itemBuilder ends
        # The itemBuilder ends with:
        #                                       ),
        #                                     ),
        #                                   );
        #                                 },
        item_builder_end = text.find(");", text.find("TextButton.icon(", text.find("delete", text.find("_confirmDeleteProduct(product)"))))
        # wait, the item builder ends when it returns the Container. The Container ends before the GridView builder ends.
        
text = text.replace("""                                    final cardQty = _cardQuantities[product.id] ?? 0;
                                    final cardCtrl = _getController('card_qty_${product.id}', '$cardQty');
  
                                    return Container(""",
"""                                    return ValueListenableBuilder<Map<int, double>>(
                                      valueListenable: _cardQuantitiesNotifier,
                                      builder: (context, cardQuantities, child) {
                                        final cardQty = cardQuantities[product.id] ?? 0;
                                        final cardCtrl = _getController('card_qty_${product.id}', '$cardQty');
                                        return GestureDetector(
                                          onTap: () {
                                            if (cardQty == 0) {
                                                _updateProductQuantity(product, product.isWeight ? product.weightIncrementStep : 1.0);
                                            }
                                          },
                                          child: Container(""")
                                          
text = text.replace("""                                                        onPressed: () => _confirmDeleteProduct(product),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),""",
"""                                                        onPressed: () => _confirmDeleteProduct(product),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    );
                                      }
                                    );
                                  },
                                ),""")


with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Applied fixes!")
