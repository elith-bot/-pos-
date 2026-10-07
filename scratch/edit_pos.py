import re

with open(r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add state variables
state_vars = """
  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> _tables = [];
  bool _isLoadingTables = false;
  Map<String, dynamic>? _activeTable;
"""
content = re.sub(r'(final Map<String, TextEditingController> _controllers = {};)', r'\1\n' + state_vars, content)

# 2. Add table methods
table_methods = """
  Future<void> _loadTables() async {
    setState(() => _isLoadingTables = true);
    final tables = await ApiService.getTables();
    if (mounted) {
      setState(() {
        _tables = tables;
        _isLoadingTables = false;
      });
    }
  }

  Future<void> _openTable(Map<String, dynamic> table) async {
    setState(() => _isLoading = true);
    final orderData = await ApiService.getTableOrder(table['id']);
    
    _cart.clear();
    _cardQuantities.clear();
    _globalDiscount = 0.0;
    
    if (orderData != null && orderData['has_order'] == true) {
      final items = orderData['order']['items'] as List;
      for (var item in items) {
        ProductModel product;
        try {
          product = _products.firstWhere((p) => p.id == item['product_id']);
        } catch (_) {
          product = ProductModel(id: item['product_id'], name: item['product_name'], imageUrl: '', purchasePrice: 0, sellingPrice: (item['unit_price'] as num).toDouble(), stockQuantity: 0, category: 'عام', isWeight: false, weightUnitGrams: 1000, weightIncrementStep: 100);
        }
        
        _cart.add(CartItemModel(
          product: product,
          quantity: (item['quantity'] as num).toDouble(),
          unitPurchasePrice: product.purchasePrice,
          unitSellingPrice: (item['unit_price'] as num).toDouble(),
          discount: 0.0,
        ));
        _cardQuantities[product.id] = (item['quantity'] as num).toDouble();
      }
    }
    
    setState(() {
      _activeTable = table;
      _selectedTabIndex = 0;
      _isLoading = false;
    });
  }

  Future<void> _saveTableOrder() async {
    if (_activeTable == null) return;
    final success = await ApiService.saveTableOrder(_activeTable!['id'], _cart);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ طلب الطاولة بنجاح'), backgroundColor: AppColors.success));
        setState(() {
          _activeTable = null;
          _cart.clear();
          _cardQuantities.clear();
          _globalDiscount = 0.0;
          _selectedTabIndex = 1; // Go back to tables
        });
        _loadTables();
      }
    }
  }

  Widget _buildTablesGrid() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('إدارة الطاولات', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontHeader, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة طاولات', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  final ctrl = TextEditingController(text: '1');
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: const Text('إضافة طاولات جديدة', style: TextStyle(color: Colors.white)),
                      content: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'عدد الطاولات',
                          labelStyle: const TextStyle(color: AppColors.textGray),
                          filled: true,
                          fillColor: AppColors.background,
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                        ElevatedButton(
                          onPressed: () async {
                            final c = int.tryParse(ctrl.text) ?? 1;
                            Navigator.pop(ctx);
                            await ApiService.createTables(c);
                            _loadTables();
                          },
                          child: const Text('تأكيد'),
                        ),
                      ],
                    ),
                  );
                },
              )
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1,
            ),
            itemCount: _tables.length,
            itemBuilder: (context, index) {
              final table = _tables[index];
              final isActive = table['is_active'] == true;
              return InkWell(
                onTap: () => _openTable(table),
                child: Container(
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.success.withOpacity(0.9) : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.table_restaurant, size: 48, color: isActive ? Colors.white : Colors.grey.shade800),
                            const SizedBox(height: 8),
                            Text(table['name'], style: TextStyle(color: isActive ? Colors.white : Colors.grey.shade900, fontSize: AppSizes.fontHeader, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(isActive ? 'مشغولة' : 'متاحة', style: TextStyle(color: isActive ? Colors.white70 : Colors.grey.shade700, fontSize: AppSizes.fontNormal)),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.danger),
                          onPressed: () async {
                            if (isActive) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن حذف طاولة مشغولة'), backgroundColor: AppColors.danger));
                              return;
                            }
                            await ApiService.deleteTable(table['id']);
                            _loadTables();
                          },
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
"""
content = re.sub(r'(Future<void> _loadProducts\(\) async {)', table_methods + r'\n  \1', content)

# 3. Modify init state to load tables
init_state_mod = """  void initState() {
    super.initState();
    _loadProducts();
    _loadTables();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }"""
content = re.sub(r'void initState\(\) \{[\s\S]*?\}', init_state_mod, content)

# 4. Modify checkoutSale call
content = content.replace("await ApiService.checkoutSale(_cart, 'نقداً', _globalDiscount);", 
                          "await ApiService.checkoutSale(_cart, 'نقداً', _globalDiscount, tableId: _activeTable?['id']);")

content = content.replace("setState(() {\n          _cart.clear();\n          _cardQuantities.clear();\n          _controllers.clear();\n          _globalDiscount = 0.0;",
                          "setState(() {\n          _cart.clear();\n          _cardQuantities.clear();\n          _controllers.clear();\n          _globalDiscount = 0.0;\n          _activeTable = null;\n")


# 5. Modify build method layout
layout_search = """            Expanded(
              flex: 75,
              child: Column(
                children: [
                  // Top Toolbar (Search, Add Product)"""

tabs_widget = """            Expanded(
              flex: 75,
              child: Column(
                children: [
                  // Tabs
                  Container(
                    color: AppColors.background,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (_activeTable != null) {
                                _activeTable = null;
                                _cart.clear();
                                _cardQuantities.clear();
                                _globalDiscount = 0.0;
                              }
                              setState(() => _selectedTabIndex = 0);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: _selectedTabIndex == 0 ? AppColors.surface : AppColors.background,
                                border: Border(bottom: BorderSide(color: _selectedTabIndex == 0 ? AppColors.primaryLight : Colors.transparent, width: 3)),
                              ),
                              child: Center(child: Text('البيع المباشر' + (_activeTable != null ? ' (إلغاء طلب الطاولة)' : ''), style: TextStyle(color: _selectedTabIndex == 0 ? AppColors.primaryLight : AppColors.textGray, fontSize: AppSizes.fontHeader, fontWeight: FontWeight.bold))),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedTabIndex = 1);
                              _loadTables();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: _selectedTabIndex == 1 ? AppColors.surface : AppColors.background,
                                border: Border(bottom: BorderSide(color: _selectedTabIndex == 1 ? AppColors.primaryLight : Colors.transparent, width: 3)),
                              ),
                              child: Center(child: Text('الطاولات', style: TextStyle(color: _selectedTabIndex == 1 ? AppColors.primaryLight : AppColors.textGray, fontSize: AppSizes.fontHeader, fontWeight: FontWeight.bold))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedTabIndex == 1)
                    Expanded(child: _isLoadingTables ? const Center(child: CircularProgressIndicator()) : _buildTablesGrid())
                  else
                    Expanded(child: Column(children: [
                      if (_activeTable != null)
                        Container(
                          color: AppColors.success.withOpacity(0.2),
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.table_restaurant, color: AppColors.success),
                              const SizedBox(width: 8),
                              Text('طلب نشط: ${_activeTable!['name']}', style: const TextStyle(color: AppColors.success, fontSize: AppSizes.fontHeader, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                  // Top Toolbar (Search, Add Product)"""

content = content.replace(layout_search, tabs_widget)

# Close the expanded column added for _selectedTabIndex == 0
products_grid_end = """                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),"""

products_grid_end_replacement = """                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                    ])),
                ],
              ),
            ),"""

content = content.replace(products_grid_end, products_grid_end_replacement)

# Also replace the print button
checkout_btn_search = """                            icon: const Icon(Icons.print, color: Colors.white),
                            label: const Text('إكمال البيع وطباعة الفاتورة',"""

checkout_btn_replace = """                            icon: const Icon(Icons.print, color: Colors.white),
                            label: Text(_activeTable != null ? 'إكمال وحساب طاولة ${_activeTable!['table_number']}' : 'إكمال البيع وطباعة الفاتورة',"""

content = content.replace(checkout_btn_search, checkout_btn_replace)

# And add the "Save Table" button above the print button if _activeTable is not null
print_btn_block_search = """                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon("""

print_btn_block_replace = """                        if (_activeTable != null) ...[
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
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon("""
content = content.replace(print_btn_block_search, print_btn_block_replace)

with open(r"c:\Users\Mac-x77\Desktop\كاشير\frontend\lib\screens\pos_screen.dart", "w", encoding="utf-8") as f:
    f.write(content)

print("Modified pos_screen.dart successfully!")
