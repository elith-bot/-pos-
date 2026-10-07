import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../core/app_theme.dart';
import '../services/file_picker_helper.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/restock_history_model.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  double? _customTotalSellingPrice;
  List<ProductModel> _products = [];
  final ValueNotifier<List<CartItemModel>> _cartNotifier = ValueNotifier([]);
  List<CartItemModel> get _cart => _cartNotifier.value;

  bool _isLoading = true;
  String _searchQuery = '';
  double? _minPrice;
  double? _maxPrice;
  int? _minStock;

  final ValueNotifier<double> _globalDiscountNotifier = ValueNotifier(0.0);
  double get _globalDiscount => _globalDiscountNotifier.value;
  set _globalDiscount(double val) => _globalDiscountNotifier.value = val;

  // Stores product card quantities (default 0 for each product)
  final ValueNotifier<Map<int, double>> _cardQuantitiesNotifier = ValueNotifier({});
  Map<int, double> get _cardQuantities => _cardQuantitiesNotifier.value;
  
  // Tracks which cart items have expanded details
  final Set<int> _expandedCartItems = {};

  // Controllers map to preserve focus while typing numbers
  final Map<String, TextEditingController> _controllers = {};

  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> _tables = [];
  bool _isLoadingTables = false;
  Map<String, dynamic>? _activeTable;

  Timer? _searchDebounce;
  Timer? _saveDebounce;

  void _debouncedSaveTableOrder() {
    if (_activeTable == null) return;
    if (_saveDebounce?.isActive ?? false) _saveDebounce!.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      ApiService.saveTableOrder(_activeTable!['id'], _cart);
    });
  }



  TextEditingController _getController(String key, String initialText) {
    if (!_controllers.containsKey(key)) {
      _controllers[key] = TextEditingController(text: initialText);
    } else {
      final ctrl = _controllers[key]!;
      // Only sync if text changed from outside and field isn't focused
      if (ctrl.text != initialText && !ctrl.selection.isValid) {
        ctrl.text = initialText;
      }
    }
    return _controllers[key]!;
  }

  String _formatQty(double qty) {
    if (qty == qty.toInt()) return qty.toInt().toString();
    return qty.toStringAsFixed(2).replaceAll(RegExp(r'([.]*0+)(?!.*\d)'), '');
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String _barcodeBuffer = '';
  DateTime? _lastKeyPress;

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final now = DateTime.now();
      if (_lastKeyPress != null && now.difference(_lastKeyPress!).inMilliseconds > 500) {
        _barcodeBuffer = '';
      }
      _lastKeyPress = now;

      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_barcodeBuffer.isNotEmpty) {
          _handleBarcodeScanned(_barcodeBuffer.trim());
          _barcodeBuffer = '';
          return true;
        }
      } else if (event.character != null) {
        _barcodeBuffer += event.character!;
      }
    }
    return false;
  }

  void _handleBarcodeScanned(String barcode) async {
    ProductModel? product;
    try {
      product = _products.firstWhere((p) => p.barcode == barcode);
    } catch (_) {
      product = await ApiService.getProductByBarcode(barcode);
    }

    if (product != null) {
      double currentQty = _cardQuantities[product.id] ?? 0.0;
      double increment = product.isWeight ? product.weightIncrementStep : 1.0;
      _updateProductQuantity(product, currentQty + increment);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة ${product.name} للسلة'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('المنتج غير موجود، يرجى إضافته.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      _showAddProductDialog(initialBarcode: barcode);
    }
  }

  @override
    void initState() {
    super.initState();
    _loadProducts();
    _loadTables();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  
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
    
    _cartNotifier.value = [];
    _cardQuantitiesNotifier.value = {};
    _globalDiscount = 0.0;
    
    if (orderData != null && orderData['has_order'] == true) {
      final items = orderData['order']['items'] as List;
      for (var item in items) {
        ProductModel product;
        try {
          product = _products.firstWhere((p) => p.id == item['product_id']);
        } catch (_) {
          product = ProductModel(id: item['product_id'], name: item['product_name'], barcode: '', imageUrl: '', purchasePrice: 0, sellingPrice: (item['unit_price'] as num).toDouble(), unitProfit: 0.0, stockQuantity: 0, category: 'عام', isWeight: false, weightUnitGrams: 1000, weightIncrementStep: 100, createdAt: DateTime.now().toIso8601String());
        }
        
        _cartNotifier.value = List.from(_cartNotifier.value)..add(CartItemModel(
          product: product,
          quantity: (item['quantity'] as num).toDouble(),
          unitPurchasePrice: product.purchasePrice,
          unitSellingPrice: (item['unit_price'] as num).toDouble(),
          discount: 0.0,
        ));
        _cardQuantitiesNotifier.value = Map.from(_cardQuantitiesNotifier.value)..[ product.id ] = (item['quantity'] as num).toDouble();
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
          _cartNotifier.value = [];
          _cardQuantitiesNotifier.value = {};
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

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final prods = await ApiService.getProducts(
      search: _searchQuery,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      minStock: _minStock,
    );
    if (mounted) {
      setState(() {
        _products = prods;
        _isLoading = false;
      });
    }
  }

  // Synchronize product card quantity with cart sidebar in real-time
  void _updateProductQuantity(ProductModel product, double newQty) {
    if (newQty < 0) newQty = 0.0;

    // No setState needed, Notifiers will handle it
      _cardQuantitiesNotifier.value = Map.from(_cardQuantitiesNotifier.value)..[ product.id ] = newQty;
      final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);

      if (newQty > 0) {
        if (existingIndex >= 0) {
          final newCart = List<CartItemModel>.from(_cartNotifier.value);
          newCart[existingIndex].quantity = newQty;
          _cartNotifier.value = newCart;
        } else {
          _cartNotifier.value = List.from(_cartNotifier.value)..add(CartItemModel(
            product: product,
            quantity: newQty,
            unitPurchasePrice: product.purchasePrice,
            unitSellingPrice: product.sellingPrice,
            discount: 0.0,
          ));
        }
      } else {
        if (existingIndex >= 0) {
          _cartNotifier.value = List.from(_cartNotifier.value)..removeAt(existingIndex);
        }
      }

      if (_cart.isEmpty) {
        _globalDiscount = 0.0;
      }

    // Update card controller text if needed
    final key = 'card_qty_${product.id}';
    if (_controllers.containsKey(key)) {
      final ctrl = _controllers[key]!;
      String textVal = newQty == newQty.toInt() ? newQty.toInt().toString() : newQty.toString();
      if (ctrl.text != textVal) {
        ctrl.text = textVal;
      }
    }
  }

  // Method to adjust overall cart total discount directly at the sale level
  void _updateCartTotalDiscount(double newTotalDiscount) {
    if (_cart.isEmpty) return;
    final double itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    _globalDiscount = newTotalDiscount - itemDiscountSum;
  }

  // Method to adjust overall cart final price directly
  void _updateCartFinalTotal(double newFinalTotal) {
    if (_cart.isEmpty) return;
    final double baseSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final double totalSellingSum = _customTotalSellingPrice ?? baseSellingSum;
    final double itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    
    double targetGlobalDiscount = totalSellingSum - itemDiscountSum - newFinalTotal;
    _globalDiscount = targetGlobalDiscount;
  }

  void _showAddProductDialog({String? initialBarcode}) {
    final nameCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController(text: initialBarcode ?? '');
    final imageCtrl = TextEditingController();
    final purchaseCtrl = TextEditingController();
    final sellingCtrl = TextEditingController();
    final stockCtrl = TextEditingController();
    final categoryCtrl = TextEditingController(text: 'عام');
    bool isWeight = false;
    final weightUnitCtrl = TextEditingController(text: '1000');
    final weightIncCtrl = TextEditingController(text: '100');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.add_business, color: AppColors.primaryLight),
                SizedBox(width: 8),
                Text('إضافة منتج جديد للمخزن', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'اسم المنتج',
                      labelStyle: const TextStyle(color: AppColors.textGray),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: barcodeCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'الباركود (رقم تسلسلي)',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        ),
                        icon: const Icon(Icons.qr_code, color: AppColors.primaryLight, size: 18),
                        label: const Text('توليد', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontSmall)),
                        onPressed: () {
                          setDialogState(() {
                            barcodeCtrl.text = DateTime.now().millisecondsSinceEpoch.toString();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Image Selection (File Picker or URL)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: imageCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'رابط الصورة أو مسارها',
                            hintText: 'https://... أو اختر من الجهاز',
                            hintStyle: const TextStyle(color: AppColors.textHint, fontSize: AppSizes.fontSmall),
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        ),
                        icon: const Icon(Icons.folder_open, color: AppColors.primaryLight, size: 18),
                        label: const Text('تصفح الجهاز', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontSmall)),
                        onPressed: () async {
                          final base64Image = await FilePickerHelper.pickImageAsBase64();
                          if (base64Image != null && base64Image.isNotEmpty) {
                            setDialogState(() {
                              imageCtrl.text = base64Image;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: purchaseCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'سعر الشراء',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sellingCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'سعر البيع',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!isWeight) ...[
                        Expanded(
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'الكمية الأوليّة',
                              labelStyle: const TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: TextField(
                          controller: categoryCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'التصنيف (القسم)',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('يباع بالوزن؟', style: TextStyle(color: Colors.white)),
                              Switch(
                                value: isWeight,
                                activeColor: AppColors.primaryLight,
                                onChanged: (val) {
                                  setDialogState(() {
                                    isWeight = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isWeight) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: weightUnitCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'الوحدة لسعر البيع (غرام)',
                              labelStyle: const TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: weightIncCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'خطوة الوزن (+/-)',
                              labelStyle: const TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: AppColors.textGray)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  await ApiService.addProduct({
                    'name': nameCtrl.text.trim(),
                    'barcode': barcodeCtrl.text.trim(),
                    'image_url': imageCtrl.text.trim(),
                    'purchase_price': double.tryParse(purchaseCtrl.text) ?? 0.0,
                    'selling_price': double.tryParse(sellingCtrl.text) ?? 0.0,
                    'stock_quantity': double.tryParse(stockCtrl.text) ?? 0,
                    'category': categoryCtrl.text.trim(),
                    'is_weight': isWeight,
                    'weight_unit_grams': int.tryParse(weightUnitCtrl.text) ?? 1000,
                    'weight_increment_step': double.tryParse(weightIncCtrl.text) ?? 100.0,
                  });
                  _loadProducts();
                },
                child: const Text('إضافة المنتج', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditProductDialog(ProductModel product) {
    final nameCtrl = TextEditingController(text: product.name);
    final barcodeCtrl = TextEditingController(text: product.barcode);
    final imageCtrl = TextEditingController(text: product.imageUrl);
    final purchaseCtrl = TextEditingController(text: product.purchasePrice.toStringAsFixed(0));
    final sellingCtrl = TextEditingController(text: product.sellingPrice.toStringAsFixed(0));
    final stockCtrl = TextEditingController(text: '${product.stockQuantity}');
    final categoryCtrl = TextEditingController(text: product.category);
    bool isWeight = product.isWeight;
    final weightUnitCtrl = TextEditingController(text: '${product.weightUnitGrams}');
    final weightIncCtrl = TextEditingController(text: '${product.weightIncrementStep}');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.edit, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Text('تعديل بيانات المنتج: ${product.name}', style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'اسم المنتج',
                      labelStyle: const TextStyle(color: AppColors.textGray),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: barcodeCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'الباركود (رقم تسلسلي)',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        ),
                        icon: const Icon(Icons.qr_code, color: AppColors.primaryLight, size: 18),
                        label: const Text('توليد', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontSmall)),
                        onPressed: () {
                          setDialogState(() {
                            barcodeCtrl.text = DateTime.now().millisecondsSinceEpoch.toString();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: imageCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'رابط الصورة أو مسارها',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        ),
                        icon: const Icon(Icons.folder_open, color: AppColors.primaryLight, size: 18),
                        label: const Text('تصفح الجهاز', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontSmall)),
                        onPressed: () async {
                          final base64Image = await FilePickerHelper.pickImageAsBase64();
                          if (base64Image != null && base64Image.isNotEmpty) {
                            setDialogState(() {
                              imageCtrl.text = base64Image;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: purchaseCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'سعر الشراء',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sellingCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'سعر البيع',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!isWeight) ...[
                        Expanded(
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'الكمية في المخزن',
                              labelStyle: const TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: TextField(
                          controller: categoryCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'التصنيف (القسم)',
                            labelStyle: const TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('يباع بالوزن؟', style: TextStyle(color: Colors.white)),
                              Switch(
                                value: isWeight,
                                activeColor: AppColors.primaryLight,
                                onChanged: (val) {
                                  setDialogState(() {
                                    isWeight = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isWeight) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: weightUnitCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'الوحدة لسعر البيع (غرام)',
                              labelStyle: const TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: weightIncCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'خطوة الوزن (+/-)',
                              labelStyle: const TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: AppColors.textGray)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  await ApiService.updateProduct(product.id, {
                    'name': nameCtrl.text.trim(),
                    'barcode': barcodeCtrl.text.trim(),
                    'image_url': imageCtrl.text.trim(),
                    'purchase_price': double.tryParse(purchaseCtrl.text) ?? 0.0,
                    'selling_price': double.tryParse(sellingCtrl.text) ?? 0.0,
                    'stock_quantity': double.tryParse(stockCtrl.text) ?? 0,
                    'category': categoryCtrl.text.trim(),
                    'is_weight': isWeight,
                    'weight_unit_grams': int.tryParse(weightUnitCtrl.text) ?? 1000,
                    'weight_increment_step': double.tryParse(weightIncCtrl.text) ?? 100.0,
                  });
                  _loadProducts();
                },
                child: const Text('حفظ التعديلات', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRestockDialog(ProductModel product) {
    final qtyCtrl = TextEditingController(text: '10');
    final purchasePriceCtrl = TextEditingController(text: product.purchasePrice.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('توريد وشراء شحنة إضافية: ${product.name}',
            style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontHeader)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'الكمية المضافة للمخزن',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: purchasePriceCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'سعر الشراء للشحنة الجديدة',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text) ?? 0;
              final price = double.tryParse(purchasePriceCtrl.text) ?? product.purchasePrice;
              if (qty > 0) {
                Navigator.pop(ctx);
                await ApiService.restockProduct(product.id, qty, price);
                _loadProducts();
              }
            },
            child: const Text('تأكيد التوريد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRestockHistoryDialog(ProductModel product) async {
    final history = await ApiService.getRestockHistory(product.id);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('سجل المشتريات: ${product.name}',
            style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontHeader)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: history.isEmpty
              ? const Center(child: Text('لا توجد سجلات شراء سابقة', style: TextStyle(color: AppColors.textGray)))
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final h = history[index];
                    return Card(
                      color: AppColors.background,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('الكمية: ${h.quantity}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('التاريخ: ${h.createdAt}', style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                        trailing: Text('السعر: ${h.purchasePrice.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق', style: TextStyle(color: AppColors.textGray))),
        ],
      ),
    );
  }

  void _confirmDeleteProduct(ProductModel product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تأكيد حذف المنتج', style: TextStyle(color: Colors.white)),
        content: Text('هل أنت متأكد من حذف ${product.name}؟', style: const TextStyle(color: AppColors.textDialog)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.deleteProduct(product.id);
              _loadProducts();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _completeCheckout() async {
    if (_cart.isEmpty) return;
    final success = await ApiService.checkoutSale(_cart, 'نقداً', _globalDiscount, tableId: _activeTable?['id']);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إكمال عملية البيع وتحديث المخزون بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _cartNotifier.value = [];
          _cardQuantitiesNotifier.value = {};
          _controllers.clear();
          _globalDiscount = 0.0;
          _activeTable = null;

        });
        _loadProducts();
      }
    }
  }

  Widget _buildProductImage(String imageUrl) {
    if (imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('data:image')) {
        try {
          final base64Data = imageUrl.split(',').last;
          final bytes = base64Decode(base64Data);
          return Image.memory(bytes, height: 140, width: double.infinity, fit: BoxFit.cover);
        } catch (_) {}
      } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        return Image.network(
          imageUrl,
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
        );
      }
    }
    return _buildPlaceholderImage();
  }

  Widget _buildPlaceholderImage() {
    return Container(
      height: 140,
      width: double.infinity,
      color: AppColors.background,
      child: Center(
        child: Icon(Icons.shopping_bag_outlined, size: 54, color: AppColors.primaryLight.withOpacity(0.7)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double totalCostSum = _cart.fold(0.0, (sum, i) => sum + i.totalPurchaseCost);
    final double totalSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final double itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    
    final double totalDiscountSum = itemDiscountSum + _globalDiscount;
    final double totalFinalAmount = totalSellingSum - totalDiscountSum;
    final double totalNetProfitSum = totalFinalAmount - totalCostSum;

    
    Widget buildProductsArea() {
      return Expanded(
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
                                _cartNotifier.value = [];
                                _cardQuantitiesNotifier.value = {};
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
                  // Top Toolbar (Search, Add Product)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: AppColors.surface,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            style: const TextStyle(color: Colors.white),
                            onChanged: (val) {
                              if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                              _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                                setState(() {
                                  _searchQuery = val;
                                });
                                _loadProducts();
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'بحث فوري في المنتجات (الاسم، التصنيف)...',
                              hintStyle: const TextStyle(color: AppColors.textHint),
                              prefixIcon: const Icon(Icons.search, color: AppColors.primaryLight),
                              filled: true,
                              fillColor: AppColors.background,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),
                        if (appPermissions.canManageProducts)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primarySolid,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                            label: const Text('إضافة منتج', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: _showAddProductDialog,
                          ),
                      ],
                    ),
                  ),

                  // Products Grid (4 items per row on desktop)
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                        : _products.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
                                    const SizedBox(height: 12),
                                    const Text('لا توجد منتجات مطابقة حالياً', style: TextStyle(color: AppColors.textGray)),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 310,
                                  mainAxisExtent: 430,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                                itemCount: _products.length,
                                itemBuilder: (context, index) {
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
                                          child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: cardQty > 0 ? AppColors.primarySolid : AppColors.border,
                                        width: cardQty > 0 ? 2 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Product Image & Stock Badge
                                        Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                              child: _buildProductImage(product.imageUrl),
                                            ),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: product.stockQuantity > 5
                                                      ? AppColors.stockHighBg
                                                      : AppColors.stockLowBg,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'المخزن: ${product.stockQuantity}',
                                                  style: TextStyle(
                                                    color: product.stockQuantity > 5
                                                        ? AppColors.stockHighText
                                                        : AppColors.stockLowText,
                                                    fontSize: AppSizes.fontSmall,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),

                                        // Card Info Body
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  product.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontTitle),
                                                ),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    if (appPermissions.canViewPurchasePrice)
                                                      Text('شراء: ${product.purchasePrice.toStringAsFixed(0)}',
                                                          style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal))
                                                    else
                                                      const Text('شراء: ***', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                                                    
                                                    if (appPermissions.canViewSellingPrice)
                                                      Text('بيع: ${product.sellingPrice.toStringAsFixed(0)}',
                                                          style: const TextStyle(
                                                              color: AppColors.primaryLight,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: AppSizes.fontMedium)),
                                                    
                                                    if (appPermissions.canViewProfit)
                                                      Text('ربح: ${product.unitProfit.toStringAsFixed(0)}',
                                                          style: const TextStyle(color: AppColors.success, fontSize: AppSizes.fontNormal))
                                                    else
                                                      const Text('ربح: ***', style: TextStyle(color: AppColors.success, fontSize: AppSizes.fontNormal)),
                                                  ],
                                                ),
                                                // Live Quantity Box (Preserves Focus while Typing)
                                                Row(
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle, color: AppColors.danger, size: 24),
                                                      onPressed: () => _updateProductQuantity(product, cardQty - (product.isWeight ? product.weightIncrementStep : 1.0)),
                                                    ),
                                                    Expanded(
                                                      child: SizedBox(
                                                        height: 36,
                                                        child: TextField(
                                                          controller: cardCtrl,
                                                          keyboardType: TextInputType.number,
                                                          textAlign: TextAlign.center,
                                                          style: const TextStyle(
                                                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                                                          decoration: InputDecoration(
                                                            filled: true,
                                                            fillColor: AppColors.background,
                                                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                                            border: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(8),
                                                              borderSide: BorderSide.none,
                                                            ),
                                                          ),
                                                          onChanged: (val) {
                                                            final q = double.tryParse(val) ?? 0.0;
                                                            _updateProductQuantity(product, q);
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.add_circle, color: AppColors.success, size: 24),
                                                      onPressed: () => _updateProductQuantity(product, cardQty + (product.isWeight ? product.weightIncrementStep : 1.0)),
                                                    ),
                                                  ],
                                                ),
                                                // Card Actions: Edit, Restock, Delete
                                                if (appPermissions.canManageProducts)
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      TextButton.icon(
                                                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 30)),
                                                        icon: const Icon(Icons.edit, color: AppColors.primaryLight, size: 14),
                                                        label: const Text('تعديل', style: TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontSmall)),
                                                        onPressed: () => _showEditProductDialog(product),
                                                      ),
                                                      TextButton.icon(
                                                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 30)),
                                                        icon: const Icon(Icons.inventory, color: AppColors.warning, size: 14),
                                                        label: const Text('توريد', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontSmall)),
                                                        onPressed: () => _showRestockDialog(product),
                                                      ),
                                                      TextButton.icon(
                                                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 30)),
                                                        icon: const Icon(Icons.history, color: AppColors.historyIcon, size: 14),
                                                        label: const Text('السجل', style: TextStyle(color: AppColors.historyIcon, fontSize: AppSizes.fontSmall)),
                                                        onPressed: () => _showRestockHistoryDialog(product),
                                                      ),
                                                      TextButton.icon(
                                                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 30)),
                                                        icon: const Icon(Icons.delete, color: AppColors.danger, size: 14),
                                                        label: const Text('حذف', style: TextStyle(color: AppColors.danger, fontSize: AppSizes.fontSmall)),
                                                        onPressed: () => _confirmDeleteProduct(product),
                                                      ),
                                                    ],
                                                  ),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: AppColors.primarySolid,
                                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    icon: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 20),
                                                    label: const Text('إضافة للسلة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                                                    onPressed: () => _updateProductQuantity(product, cardQty + (product.isWeight ? product.weightIncrementStep : 1.0)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ));
                                      },
                                    );
                                  },
                                ),
                  ),
                    ])),
                ],
              ),
            );
    }

    Widget buildCartArea() {
      return ValueListenableBuilder<List<CartItemModel>>(
      valueListenable: _cartNotifier,
      builder: (context, _cart, child) {
        final double totalCostSum = _cart.fold(0.0, (sum, i) => sum + i.totalPurchaseCost);
        final double totalSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
        final double itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
        final double totalDiscountSum = itemDiscountSum + _globalDiscount;
        final double totalFinalAmount = totalSellingSum - totalDiscountSum;
        final double totalNetProfitSum = totalFinalAmount - totalCostSum;

        return Container(
              width: double.infinity,
              color: AppColors.surface,
              child: Column(
                children: [
                  // Sidebar Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: AppColors.background,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shopping_cart, color: AppColors.primaryLight),
                            SizedBox(width: 8),
                            Text('تفاصيل الطلب والسلة (25%)',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontHeader)),
                          ],
                        ),
                        if (_cart.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _cartNotifier.value = [];
                                _cardQuantitiesNotifier.value = {};
                                _globalDiscount = 0.0;
                              });
                            },
                            child: const Text('محي السلة', style: TextStyle(color: AppColors.danger, fontSize: AppSizes.fontNormal)),
                          ),
                      ],
                    ),
                  ),

                  // Cart Items List
                  Expanded(
                    child: _cart.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.remove_shopping_cart_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
                                const SizedBox(height: 8),
                                const Text('السلة فارغة. اضغط + في كارت المنتج لإضافته',
                                    style: TextStyle(color: AppColors.textHint, fontSize: AppSizes.fontMedium)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(10),
                            itemCount: _cart.length,
                            itemBuilder: (context, index) {
                              final item = _cart[index];
                              final pId = item.product.id;

                                                            return CartItemWidget(
                                item: item,
                                onUpdate: () {
                                  _cartNotifier.value = List.from(_cartNotifier.value);
                                  if (_activeTable != null) _debouncedSaveTableOrder();
                                },
                                onUpdateQuantity: _updateProductQuantity,
                              );
                            },
                          ),
                  ),

                  // BOTTOM SUMMARY PANEL WITH FULLY EDITABLE INTERACTIVE TOTALS & FOCUS RETENTION
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: AppColors.background,
                    child: Column(
                      children: [
                        CartSummaryWidget(
                          totalCostSum: totalCostSum,
                          totalSellingSum: totalSellingSum,
                          totalDiscountSum: totalDiscountSum,
                          totalFinalAmount: totalFinalAmount,
                          totalNetProfitSum: totalNetProfitSum,
                          totalItems: _cart.length,
                          canViewPurchasePrice: appPermissions.canViewPurchasePrice,
                          canViewProfit: appPermissions.canViewProfit,
                          onUpdateTotalSelling: (newTotal) {
                            setState(() {
                              _customTotalSellingPrice = newTotal;
                            });
                          },
                          onUpdateTotalDiscount: (newDisc) {
                            setState(() {
                              _updateCartTotalDiscount(newDisc);
                            });
                          },
                          onUpdateFinalTotal: (newFinal) {
                            setState(() {
                              _updateCartFinalTotal(newFinal);
                            });
                          },
                        ),
                        const SizedBox(height: 8),

                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _cart.isNotEmpty ? AppColors.success : AppColors.border,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.print, color: Colors.white),
                            label: Text(_activeTable != null ? 'إكمال وحساب طاولة ${_activeTable!['table_number']}' : 'إكمال البيع وطباعة الفاتورة',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                            onPressed: _cart.isNotEmpty ? _completeCheckout : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 800) return const SizedBox.shrink();
          return ValueListenableBuilder<List<CartItemModel>>(
            valueListenable: _cartNotifier,
            builder: (context, cart, _) {
              final double baseSellingSum = cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final double totalSellingSum = _customTotalSellingPrice ?? baseSellingSum;
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
          );
        }
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: LayoutBuilder(
          builder: (context, constraints) {
            bool isMobile = constraints.maxWidth < 800;
            if (isMobile) {
               return buildProductsArea();
            } else {
               return Row(
                 children: [
                   Expanded(flex: 75, child: buildProductsArea()),
                   SizedBox(width: 410, child: buildCartArea()),
                 ],
               );
            }
          }
        ),
      ),
    );
  }
}


class CartSummaryWidget extends StatefulWidget {
  final double totalCostSum;
  final double totalSellingSum;
  final double totalDiscountSum;
  final double totalFinalAmount;
  final double totalNetProfitSum;
  final int totalItems;
  final bool canViewPurchasePrice;
  final bool canViewProfit;
  final Function(double) onUpdateTotalSelling;
  final Function(double) onUpdateTotalDiscount;
  final Function(double) onUpdateFinalTotal;

  const CartSummaryWidget({
    Key? key,
    required this.totalCostSum,
    required this.totalSellingSum,
    required this.totalDiscountSum,
    required this.totalFinalAmount,
    required this.totalNetProfitSum,
    required this.totalItems,
    required this.canViewPurchasePrice,
    required this.canViewProfit,
    required this.onUpdateTotalSelling,
    required this.onUpdateTotalDiscount,
    required this.onUpdateFinalTotal,
  }) : super(key: key);

  @override
  _CartSummaryWidgetState createState() => _CartSummaryWidgetState();
}

class _CartSummaryWidgetState extends State<CartSummaryWidget> {
  late TextEditingController _sumSellCtrl;
  late TextEditingController _sumDiscCtrl;
  late TextEditingController _sumFinalCtrl;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _sumSellCtrl = TextEditingController(text: widget.totalSellingSum.toStringAsFixed(0));
    _sumDiscCtrl = TextEditingController(text: widget.totalDiscountSum.toStringAsFixed(0));
    _sumFinalCtrl = TextEditingController(text: widget.totalFinalAmount.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(CartSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    String ss = widget.totalSellingSum.toStringAsFixed(0);
    if (_sumSellCtrl.text != ss) _sumSellCtrl.text = ss;

    String sd = widget.totalDiscountSum.toStringAsFixed(0);
    if (_sumDiscCtrl.text != sd) _sumDiscCtrl.text = sd;

    String sf = widget.totalFinalAmount.toStringAsFixed(0);
    if (_sumFinalCtrl.text != sf) _sumFinalCtrl.text = sf;
  }

  @override
  void dispose() {
    _sumSellCtrl.dispose();
    _sumDiscCtrl.dispose();
    _sumFinalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.background,
      margin: const EdgeInsets.only(top: 8, bottom: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'المجموع الكلي للطلب',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                  ),
                ),
                Text(
                  '(${widget.totalItems} منتجات)',
                  style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Total Selling Display
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('السعر الكلي:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                Text(
                  '${widget.totalSellingSum.toStringAsFixed(0)} د.ع',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                ),
              ],
            ),

            if (widget.totalDiscountSum > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الخصم الكلي:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal)),
                    Text(
                      '-${widget.totalDiscountSum.toStringAsFixed(0)} د.ع',
                      style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('السعر النهائي للطلب:', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: AppSizes.fontNormal)),
                Text(
                  '${widget.totalFinalAmount.toStringAsFixed(0)} د.ع',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                ),
              ],
            ),
            
            const Divider(color: Colors.white12, height: 24),
            
            // Show Details Button
            Center(
              child: TextButton.icon(
                icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.primaryLight, size: 20),
                label: Text(_isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل', style: const TextStyle(color: AppColors.primaryLight)),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 12),
              
              if (widget.canViewPurchasePrice) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مجموع سعر الشراء:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                    Text('${widget.totalCostSum.toStringAsFixed(0)} (ثابتة)', style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal)),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Edit Total Selling
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('سعر البيع الكلي:', style: TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontNormal))),
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: AppColors.primaryLight, size: 20),
                    onPressed: () => widget.onUpdateTotalSelling(widget.totalSellingSum - 500),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumSellCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final f = double.tryParse(val);
                          if (f != null) widget.onUpdateTotalSelling(f);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.primaryLight, size: 20),
                    onPressed: () => widget.onUpdateTotalSelling(widget.totalSellingSum + 500),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Edit Total Discount
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('الخصم الكلي:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal))),
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: AppColors.warning, size: 20),
                    onPressed: () => widget.onUpdateTotalDiscount(widget.totalDiscountSum - 250),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumDiscCtrl,
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
                          if (d != null) widget.onUpdateTotalDiscount(d);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.warning, size: 20),
                    onPressed: () => widget.onUpdateTotalDiscount(widget.totalDiscountSum + 250),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Edit Final Amount
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('السعر النهائي:', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.white, size: 20),
                    onPressed: () => widget.onUpdateFinalTotal((widget.totalFinalAmount - 250).clamp(0, 9999999)),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumFinalCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontLarge, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final f = double.tryParse(val);
                          if (f != null) widget.onUpdateFinalTotal(f);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.white, size: 20),
                    onPressed: () => widget.onUpdateFinalTotal((widget.totalFinalAmount + 250).clamp(0, 9999999)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              if (widget.canViewProfit) ...[
                const Divider(color: Colors.white12, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مجموع صافي الربح:', style: TextStyle(color: AppColors.success, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold)),
                    Text('${widget.totalNetProfitSum.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                  ],
                ),
              ],
            ]
          ]
        )
      )
    );
  }
}

class CartItemWidget extends StatefulWidget {
  final CartItemModel item;
  final VoidCallback onUpdate;
  final void Function(ProductModel, double) onUpdateQuantity;

  const CartItemWidget({
    Key? key,
    required this.item,
    required this.onUpdate,
    required this.onUpdateQuantity,
  }) : super(key: key);

  @override
  State<CartItemWidget> createState() => _CartItemWidgetState();
}

class _CartItemWidgetState extends State<CartItemWidget> {
  bool _isExpanded = false;

  late TextEditingController _qtyCtrl;
  late TextEditingController _unitDiscountCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _totalCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    String qStr = widget.item.quantity == widget.item.quantity.toInt()
        ? widget.item.quantity.toInt().toString()
        : widget.item.quantity.toString();
    _qtyCtrl = TextEditingController(text: qStr);
    _unitDiscountCtrl = TextEditingController(text: widget.item.discount.toStringAsFixed(0));
    _discountCtrl = TextEditingController(text: widget.item.totalDiscountAmount.toStringAsFixed(0));
    _totalCtrl = TextEditingController(text: widget.item.totalPrice.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(CartItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    String qStr = widget.item.quantity == widget.item.quantity.toInt()
        ? widget.item.quantity.toInt().toString()
        : widget.item.quantity.toString();
    if (_qtyCtrl.text != qStr) _qtyCtrl.text = qStr;

    String udStr = widget.item.discount.toStringAsFixed(0);
    if (_unitDiscountCtrl.text != udStr) _unitDiscountCtrl.text = udStr;

    String dStr = widget.item.totalDiscountAmount.toStringAsFixed(0);
    if (_discountCtrl.text != dStr) _discountCtrl.text = dStr;

    String tStr = widget.item.totalPrice.toStringAsFixed(0);
    if (_totalCtrl.text != tStr) _totalCtrl.text = tStr;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _unitDiscountCtrl.dispose();
    _discountCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    widget.item.product.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                  onPressed: () => widget.onUpdateQuantity(widget.item.product, 0),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 1. Quantity Field
            Row(
              children: [
                const SizedBox(width: 80, child: Text('الكمية/الوزن:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal))),
                IconButton(
                  icon: const Icon(Icons.remove_circle, color: AppColors.danger, size: 20),
                  onPressed: () => widget.onUpdateQuantity(widget.item.product, widget.item.quantity - (widget.item.product.isWeight ? widget.item.product.weightIncrementStep : 1.0)),
                ),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _qtyCtrl,
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
                        widget.onUpdateQuantity(widget.item.product, q);
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.success, size: 20),
                  onPressed: () => widget.onUpdateQuantity(widget.item.product, widget.item.quantity + (widget.item.product.isWeight ? widget.item.product.weightIncrementStep : 1.0)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Total Price Text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المبلغ:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                Text(
                  '${widget.item.totalSellingAmount.toStringAsFixed(0)} د.ع',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                ),
              ],
            ),
            
            // Discount Text (if any)
            if (widget.item.totalDiscountAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('مجموع الخصم:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal)),
                    Text(
                      '-${widget.item.totalDiscountAmount.toStringAsFixed(0)} د.ع',
                      style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('السعر النهائي:', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: AppSizes.fontNormal)),
                Text(
                  '${widget.item.totalPrice.toStringAsFixed(0)} د.ع',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontMedium),
                ),
              ],
            ),
            
            const Divider(color: Colors.white12, height: 24),
            
            // Show Details Button
            Center(
              child: TextButton.icon(
                icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.primaryLight, size: 20),
                label: Text(_isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل', style: const TextStyle(color: AppColors.primaryLight)),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 12),
              // Unit Discount Field Editable
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('خصم القطعة:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal))),
                  IconButton(
                    icon: const Icon(Icons.remove, color: AppColors.warning, size: 18),
                    onPressed: () {
                      widget.item.discount = (widget.item.discount - 100).clamp(0, 9999999);
                      widget.onUpdate();
                    },
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _unitDiscountCtrl,
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
                          final d = double.tryParse(val) ?? 0;
                          widget.item.discount = d;
                          widget.onUpdate();
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.warning, size: 18),
                    onPressed: () {
                      widget.item.discount += 100;
                      widget.onUpdate();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Total Discount Field Editable
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('الخصم الكلي:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal))),
                  IconButton(
                    icon: const Icon(Icons.remove, color: AppColors.warning, size: 18),
                    onPressed: () {
                      widget.item.totalDiscountAmount = (widget.item.totalDiscountAmount - 100).clamp(0, 9999999);
                      widget.onUpdate();
                    },
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _discountCtrl,
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
                          final d = double.tryParse(val) ?? 0;
                          widget.item.totalDiscountAmount = d;
                          widget.onUpdate();
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.warning, size: 18),
                    onPressed: () {
                      widget.item.totalDiscountAmount += 100;
                      widget.onUpdate();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Total Price Editable
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('السعر النهائي:', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                    onPressed: () {
                      widget.item.totalPrice = (widget.item.totalPrice - 250).clamp(0, 9999999);
                      widget.onUpdate();
                    },
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _totalCtrl,
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
                          final t = double.tryParse(val);
                          if (t != null) {
                            widget.item.totalPrice = t;
                            widget.onUpdate();
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    onPressed: () {
                      widget.item.totalPrice += 250;
                      widget.onUpdate();
                    },
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}
