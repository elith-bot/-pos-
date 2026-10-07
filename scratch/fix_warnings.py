import os
import re

pos_file = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"
with open(pos_file, "r", encoding="utf-8") as f:
    content = f.read()

# Make sure we add _debouncedSaveTableOrder to the end of _updateProductQuantity
content = re.sub(
    r'(          if \(existingIndex >= 0\) \{\n            _cart\.removeAt\(existingIndex\);\n          \}\n        \}\n      \}\);\n  \}',
    r'\1\n    _debouncedSaveTableOrder();\n  }',
    content
)

# And to _updateCartTotalDiscount
content = re.sub(
    r'setState\(\(\) => _globalDiscount = newGlobalDiscount\);\n  \}',
    r'setState(() => _globalDiscount = newGlobalDiscount);\n    _debouncedSaveTableOrder();\n  }',
    content
)

# We can also add it to cart modifications: item.unitSellingPrice, item.totalPrice, item.discount
# To fix _saveTableOrder unused warning, we should let it be accessible, but wait we removed the Save Button!
# So _saveTableOrder is unused. We can just delete it or ignore it.
content = re.sub(
    r'  Future<void> _saveTableOrder\(\) async \{[\s\S]*?\n  \}\n',
    '',
    content
)

with open(pos_file, "w", encoding="utf-8") as f:
    f.write(content)

print("Fixed warnings")
