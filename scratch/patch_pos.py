import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Add _debouncedSaveTableOrder to _updateProductQuantity
if "_debouncedSaveTableOrder();\n    }" not in text:
    text = text.replace(
        "        _globalDiscount = 0.0;\n      }\n    });\n  }",
        "        _globalDiscount = 0.0;\n      }\n    });\n    if (_activeTable != null) _debouncedSaveTableOrder();\n  }"
    )

# 2. Add to item.unitSellingPrice onChanged
text = re.sub(
    r'(setState\(\(\) => item.unitSellingPrice = p\);)',
    r'\1 if (_activeTable != null) _debouncedSaveTableOrder();',
    text
)
# same for minus/plus buttons of unitSellingPrice
text = re.sub(
    r'(setState\(\(\) => item.unitSellingPrice = \(item.unitSellingPrice [-+] [^\)]+\)\.clamp\(0, 9999999\)\);)',
    r'\1 if (_activeTable != null) _debouncedSaveTableOrder();',
    text
)

# 3. Add to item.discount onChanged
text = re.sub(
    r'(setState\(\(\) => item.discount = p\);)',
    r'\1 if (_activeTable != null) _debouncedSaveTableOrder();',
    text
)
text = re.sub(
    r'(setState\(\(\) => item.discount = \(item.discount [-+] [^\)]+\)\.clamp\(0, 9999999\)\);)',
    r'\1 if (_activeTable != null) _debouncedSaveTableOrder();',
    text
)

# 4. Add to _globalDiscount onChanged
text = re.sub(
    r'(setState\(\(\) => _globalDiscount = p\);)',
    r'\1 if (_activeTable != null) _debouncedSaveTableOrder();',
    text
)

# 5. Fix the "Direct Sale" tab behavior: 
# "البيع المباشر (إلغاء طلب الطاولة)" should just be a regular tab or we add a Back to Tables button in the header.
# Let's add a back button in the header of buildProductsArea.
back_button = """
          if (_activeTable != null)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('رجوع للطاولات'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryLight, foregroundColor: Colors.black),
                onPressed: () {
                  setState(() {
                    _activeTable = null;
                    _cart.clear();
                    _cardQuantities.clear();
                    _selectedTabIndex = 1;
                  });
                  _loadTables();
                },
              ),
            ),
"""

if "رجوع للطاولات" not in text:
    text = text.replace(
        "            const SizedBox(width: 16),\n            Expanded(",
        "            const SizedBox(width: 16),\n" + back_button + "\n            Expanded("
    )

# 6. Change InkWell issue causing slowness:
# Wait, InkWell inside GridView might feel slow if it has a splash delay.
# Let's change the onTap for the products in `pos_screen.dart`? Actually, it's the search debounce that makes it feel slow if the UI rebuilds.
# Let's just fix the bugs first.

with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Patch applied")
