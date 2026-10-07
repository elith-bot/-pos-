import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# We want to replace the `ListView.builder` contents in `buildCartArea`
# It starts from: `ListView.builder(`
# And ends before the `// Payment area (always at bottom)` or similar comment.

start_marker = "ListView.builder("
end_marker = "                                      const SizedBox(height: 6),\n\n                                      // 4. Discount"
# Wait, it's better to find `itemBuilder: (context, index) {` inside `buildCartArea`
start_idx = text.find("itemBuilder: (context, index) {", text.find("Widget buildCartArea() {"))

# find the matching closing brace for the itemBuilder
def find_matching_brace(s, start):
    count = 0
    for i in range(start, len(s)):
        if s[i] == '{':
            count += 1
        elif s[i] == '}':
            count -= 1
            if count == 0:
                return i
    return -1

end_idx = find_matching_brace(text, text.find("{", start_idx))

new_item_builder = """itemBuilder: (context, index) {
                              final item = _cartValue[index];
                              final pId = item.product.id;

                              final cartQtyCtrl = _getController('cart_qty_$pId', _formatQty(item.quantity));

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
                                              item.product.name,
                                              style: const TextStyle(
                                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                                            onPressed: () => _updateProductQuantity(item.product, 0),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // 1. Quantity Field (Focus Retained Live onChanged)
                                      Row(
                                        children: [
                                          const SizedBox(width: 80, child: Text('الكمية/الوزن:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal))),
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle, color: AppColors.danger, size: 20),
                                            onPressed: () => _updateProductQuantity(item.product, item.quantity - (item.product.isWeight ? item.product.weightIncrementStep : 1.0)),
                                          ),
                                          Expanded(
                                            child: SizedBox(
                                              height: 32,
                                              child: TextField(
                                                controller: cartQtyCtrl,
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
                                                  _updateProductQuantity(item.product, q);
                                                },
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add_circle, color: AppColors.success, size: 20),
                                            onPressed: () => _updateProductQuantity(item.product, item.quantity + (item.product.isWeight ? item.product.weightIncrementStep : 1.0)),
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
                                            '${item.totalPrice.toStringAsFixed(0)} د.ع',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                                          ),
                                        ],
                                      ),
                                      
                                      // Discount Text (if any)
                                      if (item.discount > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('الخصم:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal)),
                                              Text(
                                                '-${item.discount.toStringAsFixed(0)} د.ع',
                                                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                                              ),
                                            ],
                                          ),
                                        ),
                                      
                                      const Divider(color: Colors.white12, height: 24),
                                      
                                      // Show Details Button
                                      Center(
                                        child: TextButton.icon(
                                          icon: const Icon(Icons.expand_more, color: AppColors.primaryLight, size: 20),
                                          label: const Text('عرض التفاصيل', style: TextStyle(color: AppColors.primaryLight)),
                                          onPressed: () {
                                            // TODO: Handled in the next step
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }"""

text = text[:start_idx] + new_item_builder + text[end_idx+1:]

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Cart UI patch applied")
