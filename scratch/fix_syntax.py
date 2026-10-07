import re

file_path = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    text = f.read()

# 1. Fix ProductModel missing args
orig_prod = "product = ProductModel(id: item['product_id'], name: item['product_name'], imageUrl: '', purchasePrice: 0, sellingPrice: (item['unit_price'] as num).toDouble(), stockQuantity: 0, category: 'عام', isWeight: false, weightUnitGrams: 1000, weightIncrementStep: 100);"
new_prod = "product = ProductModel(id: item['product_id'], name: item['product_name'], barcode: '', imageUrl: '', purchasePrice: 0, sellingPrice: (item['unit_price'] as num).toDouble(), unitProfit: 0.0, stockQuantity: 0, category: 'عام', isWeight: false, weightUnitGrams: 1000, weightIncrementStep: 100, createdAt: DateTime.now());"
text = text.replace(orig_prod, new_prod)

# 2. Fix _cartValue undefined
text = text.replace("final item = _cartValue[index];", "final item = _cart[index];")

# 3. Fix the closing braces at the end of pos_screen.dart Scaffold
end_scaffold = """    );
      });
;
  }
}"""
new_end_scaffold = """    );
  }
}"""
text = text.replace(end_scaffold, new_end_scaffold)

# 4. Fix closing brackets inside GridView Builder (around 1510)
# Let's inspect the exact lines using regex.
# In patch_perf2.py, we had:
# grid_item_end_orig = "                                    );\n                                  },\n                                ),\n"
# grid_item_end_new = "                                    );\n                                      },\n                                    );\n                                  },\n                                ),\n"
# BUT fix_grid.py ALSO modified this area!
# fix_grid.py put: replacement_end = ";\n                                      },\n                                    );"
# So we got double closing brackets?
# Let's fix this manually by reading the file and replacing the broken chunk.

chunk_to_fix = """                                    ),
                                  );
                                      },
                                    );
                                },
                              ),"""
fixed_chunk = """                                    ),
                                  );
                                      },
                                    );
                                  },
                                ),"""
text = text.replace(chunk_to_fix, fixed_chunk)

# And wait, buildCartArea has missing ')' or ';' at 1654?
# Let's write the file and let dart analyze tell us the exact remaining errors.
with open(file_path, "w", encoding="utf-8") as f:
    f.write(text)

print("Applied syntax fixes!")
