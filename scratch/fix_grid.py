import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# Pattern to find the itemBuilder for the products grid
pattern = re.compile(r'itemBuilder:\s*\(context,\s*index\)\s*\{\s*final product = _products\[index\];\s*final cardQty = _cardQuantities\[product\.id\] \?\? 0;')
match = pattern.search(text)
if not match:
    print("Pattern not found!")
    exit(1)

# Find the end of the return statement
start_return = text.find("return Container(", match.end())
if start_return == -1:
    print("return Container not found!")
    exit(1)

# We need to find the matching closing brace/parenthesis for 'return Container('
open_count = 0
end_return = -1
for i in range(start_return, len(text)):
    if text[i] == '(':
        open_count += 1
    elif text[i] == ')':
        open_count -= 1
        if open_count == 0:
            end_return = i
            break

if end_return == -1:
    print("Could not find matching parenthesis for return Container")
    exit(1)

# The statement should end with ';' after ')'
end_stmt = text.find(';', end_return)

# Now we construct the replacement
replacement_start = """itemBuilder: (context, index) {
                                    final product = _products[index];
                                    return ValueListenableBuilder<Map<int, double>>(
                                      valueListenable: _cardQuantitiesNotifier,
                                      builder: (context, cardQuantities, child) {
                                        final cardQty = cardQuantities[product.id] ?? 0;
                                        final String fQty = _formatQty(cardQty);
                                        final cardCtrl = _getController('card_qty_${product.id}', fQty);
                                        if (double.tryParse(cardCtrl.text) != cardQty && cardCtrl.text != fQty) {
                                          cardCtrl.text = fQty;
                                        }

                                        return GestureDetector(
                                          onTap: () {
                                            if (cardQty == 0) {
                                              _updateProductQuantity(product, product.isWeight ? product.weightIncrementStep : 1.0);
                                            }
                                          },
                                          child: """

replacement_end = """;
                                      },
                                    );"""

# The chunk from `return Container(` to `)` is `text[start_return + 7 : end_stmt]` roughly.
# Wait, `start_return` points to `return Container(`. So `text[start_return]` is `r`.
# `text[start_return + 7]` is `C`.

new_text = text[:match.start()] + replacement_start + text[start_return + 7 : end_stmt] + replacement_end + text[end_stmt+1:]

with open(file_path, "w", encoding="utf-8") as f:
    f.write(new_text)

print("Applied fix!")
