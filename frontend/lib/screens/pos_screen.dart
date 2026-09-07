import 'dart:convert';
import 'package:flutter/material.dart';
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
  List<ProductModel> _products = [];
  List<CartItemModel> _cart = [];

  bool _isLoading = true;
  String _searchQuery = '';
  double? _minPrice;
  double? _maxPrice;
  int? _minStock;

  double _globalDiscount = 0.0;

  // Stores product card quantities (default 0 for each product)
  final Map<int, double> _cardQuantities = {};
  
  // Tracks which cart items have expanded details
  final Set<int> _expandedCartItems = {};

  // Controllers map to preserve focus while typing numbers
  final Map<String, TextEditingController> _controllers = {};

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
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
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

    setState(() {
      _cardQuantities[product.id] = newQty;
      final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);

      if (newQty > 0) {
        if (existingIndex >= 0) {
          _cart[existingIndex].quantity = newQty;
        } else {
          _cart.add(CartItemModel(
            product: product,
            quantity: newQty,
            unitPurchasePrice: product.purchasePrice,
            unitSellingPrice: product.sellingPrice,
            discount: 0.0,
          ));
        }
      } else {
        if (existingIndex >= 0) {
          _cart.removeAt(existingIndex);
        }
      }

      if (_cart.isEmpty) {
        _globalDiscount = 0.0;
      }
    });

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
    setState(() {
      _globalDiscount = newTotalDiscount; // Allow negative values
    });
  }

  // Method to adjust overall cart final price directly
  void _updateCartFinalTotal(double newFinalTotal) {
    if (_cart.isEmpty) return;
    final totalSellingSum = _cart.fold(0.0, (sum, i) => sum + i.totalSellingAmount);
    final itemDiscountSum = _cart.fold(0.0, (sum, i) => sum + i.totalDiscountAmount);
    
    // newFinalTotal = totalSellingSum - itemDiscountSum - globalDiscount
    // globalDiscount = totalSellingSum - itemDiscountSum - newFinalTotal
    double targetGlobalDiscount = totalSellingSum - itemDiscountSum - newFinalTotal;
    _updateCartTotalDiscount(targetGlobalDiscount);
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
    final success = await ApiService.checkoutSale(_cart, 'نقداً', _globalDiscount);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إكمال عملية البيع وتحديث المخزون بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _cart.clear();
          _cardQuantities.clear();
          _controllers.clear();
          _globalDiscount = 0.0;
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            // 75% MAIN PRODUCTS AREA
            Expanded(
              flex: 75,
              child: Column(
                children: [
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
                              _searchQuery = val;
                              _loadProducts();
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
                                  final cardQty = _cardQuantities[product.id] ?? 0;
                                  final cardCtrl = _getController('card_qty_${product.id}', '$cardQty');

                                  return Container(
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
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),

            // 25% SIDEBAR CART & ORDER AREA WITH FULLY EDITABLE INTERACTIVE TOTALS
            Container(
              width: 410,
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
                                _cart.clear();
                                _cardQuantities.clear();
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

                              final cartQtyCtrl = _getController('cart_qty_$pId', _formatQty(item.quantity));
                              final cartSellCtrl = _getController('cart_sell_$pId', item.unitSellingPrice.toStringAsFixed(0));
                              final cartDiscCtrl = _getController('cart_disc_$pId', item.discount.toStringAsFixed(0));
                              final cartTotCtrl = _getController('cart_tot_$pId', item.totalPrice.toStringAsFixed(0));

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
                                      const SizedBox(height: 6),

                                      // 2. Selling Price (Focus Retained Live onChanged)
                                      Row(
                                        children: [
                                          const SizedBox(width: 80, child: Text('سعر البيع:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal))),
                                          IconButton(
                                            icon: const Icon(Icons.remove, color: AppColors.primaryLight, size: 18),
                                            onPressed: () => setState(() => item.unitSellingPrice = (item.unitSellingPrice - 250).clamp(0, 9999999)),
                                          ),
                                          Expanded(
                                            child: SizedBox(
                                              height: 32,
                                              child: TextField(
                                                controller: cartSellCtrl,
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
                                                  final p = double.tryParse(val);
                                                  if (p != null) setState(() => item.unitSellingPrice = p);
                                                },
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add, color: AppColors.primaryLight, size: 18),
                                            onPressed: () => setState(() => item.unitSellingPrice += 250),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      // 3. Total Price (Focus Retained Live onChanged)
                                      Row(
                                        children: [
                                          const SizedBox(width: 80, child: Text('الإجمالي الكلي:', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                                          IconButton(
                                            icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                                            onPressed: () => setState(() => item.totalPrice = (item.totalPrice - 250).clamp(0, 9999999)),
                                          ),
                                          Expanded(
                                            child: SizedBox(
                                              height: 32,
                                              child: TextField(
                                                controller: cartTotCtrl,
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
                                                  if (t != null) setState(() => item.totalPrice = t);
                                                },
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add, color: Colors.white, size: 18),
                                            onPressed: () => setState(() => item.totalPrice += 250),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      // 4. Discount (Focus Retained Live onChanged, supports negative!)
                                      Row(
                                        children: [
                                          const SizedBox(width: 80, child: Text('الخصم:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal))),
                                          IconButton(
                                            icon: const Icon(Icons.remove, color: AppColors.warning, size: 18),
                                            onPressed: () => setState(() => item.discount -= 100),
                                          ),
                                          Expanded(
                                            child: SizedBox(
                                              height: 32,
                                              child: TextField(
                                                controller: cartDiscCtrl,
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
                                                  if (d != null) setState(() => item.discount = d);
                                                },
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add, color: AppColors.warning, size: 18),
                                            onPressed: () => setState(() => item.discount += 100),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      
                                      // Toggle Details Button
                                      Center(
                                        child: TextButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              if (_expandedCartItems.contains(pId)) {
                                                _expandedCartItems.remove(pId);
                                              } else {
                                                _expandedCartItems.add(pId);
                                              }
                                            });
                                          },
                                          icon: Icon(
                                            _expandedCartItems.contains(pId) ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                            size: 16,
                                            color: AppColors.primaryLight,
                                          ),
                                          label: Text(
                                            _expandedCartItems.contains(pId) ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
                                            style: const TextStyle(fontSize: AppSizes.fontNormal, color: AppColors.primaryLight),
                                          ),
                                        ),
                                      ),
                                      
                                      // Hidden Details (Purchase Price & Net Profit)
                                      if (_expandedCartItems.contains(pId)) ...[
                                        const Divider(color: AppColors.border),
                                        const SizedBox(height: 6),
                                        if (appPermissions.canViewPurchasePrice) ...[
                                          Row(
                                            children: [
                                              const SizedBox(width: 80, child: Text('سعر الشراء:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal))),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
                                                child: Text('${item.unitPurchasePrice.toStringAsFixed(0)} (ثابتة)',
                                                    style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                        ],
                                        if (appPermissions.canViewProfit)
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('صافي الربح:', style: TextStyle(color: AppColors.success, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold)),
                                              Text(
                                                '${item.netProfit.toStringAsFixed(0)}',
                                                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
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
                        // 1. Total Purchase Cost (Fixed)
                        if (appPermissions.canViewPurchasePrice) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('مجموع سعر الشراء:', style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontNormal)),
                              Text('${totalCostSum.toStringAsFixed(0)} (ثابتة)', style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontNormal)),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],

                        // 2. Total Selling Price (Editable with + / -)
                        Row(
                          children: [
                            const SizedBox(width: 110, child: Text('مجموع سعر البيع:', style: TextStyle(color: AppColors.primaryLight, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                            IconButton(
                              icon: const Icon(Icons.remove, color: AppColors.primaryLight, size: 18),
                              onPressed: () {
                                if (totalSellingSum > 0) {
                                  double ratio = (totalSellingSum - 500) / totalSellingSum;
                                  setState(() {
                                    for (var i in _cart) { i.unitSellingPrice *= ratio; }
                                  });
                                }
                              },
                            ),
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _getController('sum_sell', totalSellingSum.toStringAsFixed(0)),
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
                                    final newSumSell = double.tryParse(val);
                                    if (newSumSell != null && totalSellingSum > 0) {
                                      double ratio = newSumSell / totalSellingSum;
                                      setState(() {
                                        for (var i in _cart) { i.unitSellingPrice *= ratio; }
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: AppColors.primaryLight, size: 18),
                              onPressed: () {
                                if (totalSellingSum > 0) {
                                  double ratio = (totalSellingSum + 500) / totalSellingSum;
                                  setState(() {
                                    for (var i in _cart) { i.unitSellingPrice *= ratio; }
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // 3. Total Discount (Editable with + / -)
                        Row(
                          children: [
                            const SizedBox(width: 110, child: Text('مجموع الخصم:', style: TextStyle(color: AppColors.warning, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold))),
                            IconButton(
                              icon: const Icon(Icons.remove, color: AppColors.warning, size: 18),
                              onPressed: () => _updateCartTotalDiscount(totalDiscountSum - 250),
                            ),
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _getController('sum_disc', totalDiscountSum.toStringAsFixed(0)),
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
                                    if (d != null) _updateCartTotalDiscount(d);
                                  },
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: AppColors.warning, size: 18),
                              onPressed: () => _updateCartTotalDiscount(totalDiscountSum + 250),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // 4. Total Net Profit (Fixed calculated)
                        if (appPermissions.canViewProfit) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('مجموع صافي الربح:', style: TextStyle(color: AppColors.success, fontSize: AppSizes.fontNormal, fontWeight: FontWeight.bold)),
                              Text('${totalNetProfitSum.toStringAsFixed(0)}',
                                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                            ],
                          ),
                          const Divider(color: AppColors.border, height: 16),
                        ],

                        // 5. Final Total Amount (Editable with + / -)
                        Row(
                          children: [
                            const SizedBox(width: 110, child: Text('السعر الكلي النهائي:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontNormal))),
                            IconButton(
                              icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                              onPressed: () => _updateCartFinalTotal((totalFinalAmount - 250).clamp(0, 9999999)),
                            ),
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _getController('sum_final', totalFinalAmount.toStringAsFixed(0)),
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
                                    if (f != null) _updateCartFinalTotal(f);
                                  },
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: Colors.white, size: 18),
                              onPressed: () => _updateCartFinalTotal(totalFinalAmount + 250),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _cart.isNotEmpty ? AppColors.success : AppColors.border,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.print, color: Colors.white),
                            label: const Text('إكمال البيع وطباعة الفاتورة',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontLarge)),
                            onPressed: _cart.isNotEmpty ? _completeCheckout : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
