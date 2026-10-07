import os

pos_file = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"
with open(pos_file, "r", encoding="utf-8") as f:
    content = f.read()

# Make sure we add _debouncedSaveTableOrder to the end of _updateProductQuantity
search_str1 = """      if (existingIndex >= 0) {
        _cart.removeAt(existingIndex);
      }
    }
  }"""
replace_str1 = """      if (existingIndex >= 0) {
        _cart.removeAt(existingIndex);
      }
    }
    _debouncedSaveTableOrder();
  }"""
content = content.replace(search_str1, replace_str1)

search_str2 = """    setState(() => _globalDiscount = newGlobalDiscount);
  }"""
replace_str2 = """    setState(() => _globalDiscount = newGlobalDiscount);
    _debouncedSaveTableOrder();
  }"""
content = content.replace(search_str2, replace_str2)

with open(pos_file, "w", encoding="utf-8") as f:
    f.write(content)

print("Fixed")
