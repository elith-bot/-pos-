import re
import os

# --- 1. Patch app.py ---
app_file = r"c:\Users\Mac-x77\Desktop\كاشير\backend\app.py"
with open(app_file, "r", encoding="utf-8") as f:
    app_content = f.read()

get_tables_search = """@app.route('/api/tables', methods=['GET'])
def get_tables():
    tables = Table.query.all()
    return jsonify([{
        'id': t.id,
        'table_number': t.table_number,
        'name': t.name,
        'is_active': t.is_active
    } for t in tables])"""

get_tables_replace = """@app.route('/api/tables', methods=['GET'])
def get_tables():
    tables = Table.query.all()
    result = []
    for t in tables:
        total_price = 0.0
        if t.is_active:
            order = ActiveOrder.query.filter_by(table_id=t.id).first()
            if order:
                items = ActiveOrderItem.query.filter_by(active_order_id=order.id).all()
                for i in items:
                    total_price += (i.unit_price * i.quantity)
        result.append({
            'id': t.id,
            'table_number': t.table_number,
            'name': t.name,
            'is_active': t.is_active,
            'total_price': total_price
        })
    return jsonify(result)"""

app_content = app_content.replace(get_tables_search, get_tables_replace)

with open(app_file, "w", encoding="utf-8") as f:
    f.write(app_content)

# --- 2. Patch pos_screen.dart ---
pos_file = r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart"
with open(pos_file, "r", encoding="utf-8") as f:
    pos_content = f.read()

# Add import dart:async if not there
if "import 'dart:async';" not in pos_content:
    pos_content = pos_content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'dart:async';")

# Add Timers
timers_code = """
  Timer? _searchDebounce;
  Timer? _saveDebounce;

  void _debouncedSaveTableOrder() {
    if (_activeTable == null) return;
    if (_saveDebounce?.isActive ?? false) _saveDebounce!.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      ApiService.saveTableOrder(_activeTable!['id'], _cart);
    });
  }
"""
pos_content = pos_content.replace("  Map<String, dynamic>? _activeTable;", "  Map<String, dynamic>? _activeTable;\n" + timers_code)

# Replace _updateProductQuantity to call _debouncedSaveTableOrder
update_qty_search = """      _cart.removeAt(index);
    }
  }"""
update_qty_replace = """      _cart.removeAt(index);
    }
    _debouncedSaveTableOrder();
  }"""
pos_content = pos_content.replace(update_qty_search, update_qty_replace)

# We also need to add it to _updateCartTotalDiscount, _updateCartFinalTotal, etc.
# Just search and replace them
pos_content = pos_content.replace(
    "setState(() => _globalDiscount = newGlobalDiscount);", 
    "setState(() => _globalDiscount = newGlobalDiscount);\n    _debouncedSaveTableOrder();")

# Debounce search
search_onchanged_search = """                            onChanged: (val) {
                              _searchQuery = val;
                              _loadProducts();
                            },"""
search_onchanged_replace = """                            onChanged: (val) {
                              if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                              _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                                setState(() {
                                  _searchQuery = val;
                                });
                                _loadProducts();
                              });
                            },"""
pos_content = pos_content.replace(search_onchanged_search, search_onchanged_replace)

# Table Grid UI
table_grid_search = """                            const SizedBox(height: 4),
                            Text(isActive ? 'مشغولة' : 'متاحة', style: TextStyle(color: isActive ? Colors.white70 : Colors.grey.shade700, fontSize: AppSizes.fontNormal)),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton("""

table_grid_replace = """                            const SizedBox(height: 4),
                            Text(isActive ? 'مشغولة' : 'متاحة', style: TextStyle(color: isActive ? Colors.white70 : Colors.grey.shade700, fontSize: AppSizes.fontNormal)),
                            if (isActive && table['total_price'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text('${table['total_price']} د.ع', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                              ),
                          ],
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          left: 4,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2), elevation: 0),
                            icon: const Icon(Icons.payment, color: Colors.white, size: 16),
                            label: const Text('دفع السعر', style: TextStyle(color: Colors.white)),
                            onPressed: () => _openTable(table),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton("""
pos_content = pos_content.replace(table_grid_search, table_grid_replace)

# Hide Save button since auto-save handles it
save_btn_search = """                        if (_activeTable != null) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                              icon: const Icon(Icons.save, color: Colors.white),
                              label: const Text('حفظ الطلب للطاولة (مؤقتاً)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                              onPressed: _cart.isNotEmpty ? _saveTableOrder : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],"""
pos_content = pos_content.replace(save_btn_search, "")

with open(pos_file, "w", encoding="utf-8") as f:
    f.write(pos_content)

print("Patch applied")
