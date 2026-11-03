import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../core/app_theme.dart';
import '../services/theme_service.dart';
import '../services/file_picker_helper.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';
import '../widgets/product_masonry.dart';
import '../widgets/product_photo_body.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => PosScreenState();
}

class PosScreenState extends State<PosScreen> {
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
  final ValueNotifier<Map<int, double>> _cardQuantitiesNotifier = ValueNotifier(
    {},
  );
  Map<int, double> get _cardQuantities => _cardQuantitiesNotifier.value;

  // Controllers map to preserve focus while typing numbers
  final Map<String, TextEditingController> _controllers = {};

  int _selectedTabIndex = 0;
  List<Map<String, dynamic>> _tables = [];
  bool _isLoadingTables = false;
  Map<String, dynamic>? _activeTable;

  Timer? _searchDebounce;
  Timer? _saveDebounce;
  bool _busy = false;
  String? _checkoutKey;
  Future<bool> _saveTail = Future.value(true);
  void _notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> prepareToLeave() async {
    if (_busy) return false;
    _saveDebounce?.cancel();
    if (_activeTable == null) return true;
    setState(() => _busy = true);
    final ok = await _queueSave();
    if (mounted) setState(() => _busy = false);
    return ok;
  }

  Future<bool> _queueSave() {
    if (_activeTable == null) return Future.value(true);
    final id = _activeTable!['id'] as int;
    final items = _cart
        .map(
          (i) => CartItemModel(
            product: i.product,
            quantity: i.quantity,
            unitPurchasePrice: i.unitPurchasePrice,
            unitSellingPrice: i.unitSellingPrice,
            discount: i.discount,
          ),
        )
        .toList();
    final discount = _globalDiscount;
    _saveTail = _saveTail.then((_) async {
      final ok = await ApiService.saveTableOrder(
        id,
        items,
        globalDiscount: discount,
      );
      if (!ok) _notice('لم تُحفظ الطاولة: ${ApiService.lastError}');
      return ok;
    });
    return _saveTail;
  }

  void _debouncedSaveTableOrder() {
    if (_activeTable == null) return;
    if (_saveDebounce?.isActive ?? false) _saveDebounce!.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_activeTable != null) {
        _queueSave();
      }
    });
  }

  Future<void> _returnToTables() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_activeTable != null) {
      _saveDebounce?.cancel();
      if (!await _queueSave()) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _activeTable = null;
      _cartNotifier.value = [];
      _cardQuantitiesNotifier.value = {};
      _globalDiscount = 0.0;
      _customTotalSellingPrice = null;
      _selectedTabIndex = 1;
      _checkoutKey = null;
    });
    await _loadTables();
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
    _productSearch.dispose();
    _searchDebounce?.cancel();
    _saveDebounce?.cancel();
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String _barcodeBuffer = '';
  DateTime? _lastKeyPress;

  bool _handleKeyEvent(KeyEvent event) {
    if (_busy ||
        !TickerMode.of(context) ||
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<EditableText>() !=
            null)
      return false;
    if (event is KeyDownEvent) {
      final now = DateTime.now();
      if (_lastKeyPress != null &&
          now.difference(_lastKeyPress!).inMilliseconds > 500) {
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
      if (appPermissions.canManageProducts)
        _showAddProductDialog(initialBarcode: barcode);
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadTables();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    ThemeService.themeModeNotifier.addListener(_onThemeChanged);
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
    if (_busy) return;
    if (!await prepareToLeave()) return;
    if (_activeTable == null && _cart.isNotEmpty) {
      _notice('أكمل أو امسح سلة البيع المباشر قبل فتح طاولة.');
      return;
    }
    setState(() => _busy = true);
    final orderData = await ApiService.getTableOrder(table['id']);

    if (!mounted) return;
    if (orderData == null) {
      setState(() => _busy = false);
      _notice(ApiService.lastError);
      return;
    }
    _activeTable = null;
    _cartNotifier.value = [];
    _cardQuantitiesNotifier.value = {};
    _globalDiscount = 0.0;
    _customTotalSellingPrice = null;
    _checkoutKey = null;

    if (orderData['has_order'] == true) {
      final snapshot = orderData['order']['cart_state'];
      final items = (snapshot?['items'] ?? orderData['order']['items']) as List;
      _globalDiscount = (snapshot?['global_discount'] as num?)?.toDouble() ?? 0;
      for (var item in items) {
        ProductModel product;
        try {
          product = _products.firstWhere((p) => p.id == item['product_id']);
        } catch (_) {
          product = ProductModel(
            id: item['product_id'],
            name: item['product_name'],
            barcode: '',
            imageUrl: '',
            purchasePrice: 0,
            sellingPrice:
                ((item['unit_selling_price'] ?? item['unit_price']) as num)
                    .toDouble(),
            unitProfit: 0.0,
            stockQuantity: 0,
            category: 'عام',
            isWeight: item['is_weight'] == true,
            weightUnitGrams: item['weight_unit_grams'] ?? 1000,
            weightIncrementStep: 100,
            createdAt: DateTime.now().toIso8601String(),
          );
        }

        _cartNotifier.value = List.from(_cartNotifier.value)
          ..add(
            CartItemModel(
              product: product,
              quantity: (item['quantity'] as num).toDouble(),
              unitPurchasePrice: product.purchasePrice,
              unitSellingPrice:
                  ((item['unit_selling_price'] ?? item['unit_price']) as num)
                      .toDouble(),
              discount: (item['discount'] as num?)?.toDouble() ?? 0,
            ),
          );
        _cardQuantitiesNotifier.value = Map.from(_cardQuantitiesNotifier.value)
          ..[product.id] = (item['quantity'] as num).toDouble();
      }
    }

    setState(() {
      _busy = false;
      _activeTable = table;
      _selectedTabIndex = 0;
      _isLoading = false;
    });
  }

  String _tableFilter = 'all';

  Widget _panel(Widget child) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );

  Future<void> _selectSection(int index) async {
    FocusScope.of(context).unfocus();
    if (_busy) return;
    if (index == 1 && _activeTable != null) {
      await _returnToTables();
      return;
    }
    setState(() => _selectedTabIndex = index);
    if (index == 1) await _loadTables();
  }

  Widget _buildTablesGrid() {
    final occupied = _tables.where((t) => t['is_active'] == true).length;
    final visible = _tables
        .where(
          (t) =>
              _tableFilter == 'all' ||
              (t['is_active'] == true) == (_tableFilter == 'busy'),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final filter in [
                ('all', 'الكل (${_tables.length})'),
                ('busy', 'مشغولة ($occupied)'),
                ('free', 'متاحة (${_tables.length - occupied})'),
              ])
                ChoiceChip(
                  label: Text(filter.$2),
                  selected: _tableFilter == filter.$1,
                  onSelected: (_) => setState(() => _tableFilter = filter.$1),
                ),
              IconButton(
                tooltip: 'تحديث الطاولات',
                onPressed: _loadTables,
                icon: const Icon(Icons.refresh),
              ),
              if (appPermissions.canManageProducts)
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة طاولات'),
                  onPressed: () {
                    final ctrl = TextEditingController(text: '1');
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.surface,
                        title: Text(
                          'إضافة طاولات جديدة',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                        content: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'عدد الطاولات',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('إلغاء'),
                          ),
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
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingTables
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
              ? _emptyState(
                  Icons.table_restaurant_outlined,
                  'لا توجد طاولات في هذا القسم',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 210).floor().clamp(
                      1,
                      8,
                    );
                    return GridView.builder(
                      key: const PageStorageKey('pos-tables'),
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent:
                            260 +
                            (MediaQuery.textScalerOf(context).scale(1) - 1)
                                    .clamp(0, 2) *
                                120,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final table = visible[index];
                        final active = table['is_active'] == true;
                        final color = active
                            ? AppColors.primaryLight
                            : AppColors.stockHighText;
                        return _panel(
                          InkWell(
                            key: ValueKey('table-${table['id']}'),
                            onTap: () => _openTable(table),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: color.withValues(
                                          alpha: .10,
                                        ),
                                        child: Icon(
                                          Icons.table_restaurant_outlined,
                                          color: color,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (appPermissions.canManageProducts)
                                        IconButton(
                                          tooltip: 'حذف الطاولة',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          color: AppColors.textSecondary,
                                          onPressed: () async {
                                            if (active) {
                                              _notice(
                                                'لا يمكن حذف طاولة مشغولة',
                                              );
                                              return;
                                            }
                                            final confirmed =
                                                await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: Text(
                                                      'حذف ${table['name']}؟',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              false,
                                                            ),
                                                        child: const Text(
                                                          'إلغاء',
                                                        ),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          'حذف',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                            if (confirmed != true) return;
                                            await ApiService.deleteTable(
                                              table['id'],
                                            );
                                            if (mounted) await _loadTables();
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    table['name'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 19,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    active
                                        ? 'مشغولة • طلب محفوظ'
                                        : 'متاحة لطلب جديد',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    active
                                        ? '${table['total_price'] ?? 0} د.ع'
                                        : 'ابدأ بإضافة المنتجات',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          active
                                              ? 'فتح الطلب والحساب'
                                              : 'فتح الطاولة',
                                          style: TextStyle(
                                            color: AppColors.primaryLight,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_left,
                                        color: AppColors.primaryLight,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState(IconData icon, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );

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
    if (_busy || !newQty.isFinite) return;
    if (newQty < 0) newQty = 0.0;
    final current =
        _cart.where((i) => i.product.id == product.id).firstOrNull?.quantity ??
        0;
    final available =
        _products.where((p) => p.id == product.id).firstOrNull?.stockQuantity ??
        product.stockQuantity;
    if (newQty > available && newQty > current) {
      _notice(
        available <= 0
            ? 'نفد مخزون هذا المنتج.'
            : 'المتاح فقط: ${_formatQty(available)}${product.isWeight ? ' غم' : ''}',
      );
      _cardQuantitiesNotifier.value = Map.from(_cardQuantitiesNotifier.value);
      _cartNotifier.value = List.from(_cart);
      return;
    }

    // No setState needed, Notifiers will handle it
    _cardQuantitiesNotifier.value = Map.from(_cardQuantitiesNotifier.value)
      ..[product.id] = newQty;
    final existingIndex = _cart.indexWhere(
      (item) => item.product.id == product.id,
    );

    if (newQty > 0) {
      if (existingIndex >= 0) {
        final newCart = List<CartItemModel>.from(_cartNotifier.value);
        newCart[existingIndex].quantity = newQty;
        _cartNotifier.value = newCart;
      } else {
        _cartNotifier.value = List.from(_cartNotifier.value)
          ..add(
            CartItemModel(
              product: product,
              quantity: newQty,
              unitPurchasePrice: product.purchasePrice,
              unitSellingPrice: product.sellingPrice,
              discount: 0.0,
            ),
          );
      }
    } else {
      if (existingIndex >= 0) {
        _cartNotifier.value = List.from(_cartNotifier.value)
          ..removeAt(existingIndex);
      }
    }

    if (_cart.isEmpty) {
      _globalDiscount = 0.0;
    }

    // حفظ محتويات الطاولة تلقائياً بعد أي تغيير في الكمية.
    if (_activeTable != null) _debouncedSaveTableOrder();

    // Update card controller text if needed
    final key = 'card_qty_${product.id}';
    if (_controllers.containsKey(key)) {
      final ctrl = _controllers[key]!;
      String textVal = newQty == newQty.toInt()
          ? newQty.toInt().toString()
          : newQty.toString();
      if (ctrl.text != textVal) {
        ctrl.text = textVal;
      }
    }
  }

  // Method to adjust overall cart total discount directly at the sale level
  void _updateCartTotalDiscount(double newTotalDiscount) {
    if (_cart.isEmpty) return;
    final double itemDiscountSum = _cart.fold(
      0.0,
      (sum, i) => sum + i.totalDiscountAmount,
    );
    _globalDiscount = newTotalDiscount - itemDiscountSum;
  }

  // Method to adjust overall cart final price directly
  void _updateCartFinalTotal(double newFinalTotal) {
    if (_cart.isEmpty) return;
    final double baseSellingSum = _cart.fold(
      0.0,
      (sum, i) => sum + i.totalSellingAmount,
    );
    final double totalSellingSum = _customTotalSellingPrice ?? baseSellingSum;
    final double itemDiscountSum = _cart.fold(
      0.0,
      (sum, i) => sum + i.totalDiscountAmount,
    );

    double targetGlobalDiscount =
        totalSellingSum - itemDiscountSum - newFinalTotal;
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.add_business, color: AppColors.primaryLight),
                SizedBox(width: 8),
                Text(
                  'إضافة منتج جديد للمخزن',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppSizes.fontXLarge,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'اسم المنتج',
                      labelStyle: TextStyle(color: AppColors.textGray),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: barcodeCtrl,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'الباركود (رقم تسلسلي)',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 14,
                          ),
                        ),
                        icon: Icon(
                          Icons.qr_code,
                          color: AppColors.primaryLight,
                          size: 18,
                        ),
                        label: const Text(
                          'توليد',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.fontSmall,
                          ),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            barcodeCtrl.text = DateTime.now()
                                .millisecondsSinceEpoch
                                .toString();
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
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'رابط الصورة أو مسارها',
                            hintText: 'https://... أو اختر من الجهاز',
                            hintStyle: TextStyle(
                              color: AppColors.textHint,
                              fontSize: AppSizes.fontSmall,
                            ),
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 14,
                          ),
                        ),
                        icon: Icon(
                          Icons.folder_open,
                          color: AppColors.primaryLight,
                          size: 18,
                        ),
                        label: const Text(
                          'تصفح الجهاز',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.fontSmall,
                          ),
                        ),
                        onPressed: () async {
                          final base64Image =
                              await FilePickerHelper.pickImageAsBase64();
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
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'سعر الشراء',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sellingCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'سعر البيع',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'الكمية الأوليّة',
                              labelStyle: TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: TextField(
                          controller: categoryCtrl,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'التصنيف (القسم)',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'يباع بالوزن؟',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
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
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'الوحدة لسعر البيع (غرام)',
                              labelStyle: TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: weightIncCtrl,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'خطوة الوزن (+/-)',
                              labelStyle: TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'إلغاء',
                  style: TextStyle(color: AppColors.textGray),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primarySolid,
                ),
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
                    'weight_unit_grams':
                        int.tryParse(weightUnitCtrl.text) ?? 1000,
                    'weight_increment_step':
                        double.tryParse(weightIncCtrl.text) ?? 100.0,
                  });
                  _loadProducts();
                },
                child: const Text(
                  'إضافة المنتج',
                  style: TextStyle(color: Colors.white),
                ),
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
    final purchaseCtrl = TextEditingController(
      text: product.purchasePrice.toStringAsFixed(0),
    );
    final sellingCtrl = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(0),
    );
    final stockCtrl = TextEditingController(text: '${product.stockQuantity}');
    final categoryCtrl = TextEditingController(text: product.category);
    bool isWeight = product.isWeight;
    final weightUnitCtrl = TextEditingController(
      text: '${product.weightUnitGrams}',
    );
    final weightIncCtrl = TextEditingController(
      text: '${product.weightIncrementStep}',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.edit, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Text(
                  'تعديل بيانات المنتج: ${product.name}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppSizes.fontXLarge,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'اسم المنتج',
                      labelStyle: TextStyle(color: AppColors.textGray),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: barcodeCtrl,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'الباركود (رقم تسلسلي)',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 14,
                          ),
                        ),
                        icon: Icon(
                          Icons.qr_code,
                          color: AppColors.primaryLight,
                          size: 18,
                        ),
                        label: const Text(
                          'توليد',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.fontSmall,
                          ),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            barcodeCtrl.text = DateTime.now()
                                .millisecondsSinceEpoch
                                .toString();
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
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'رابط الصورة أو مسارها',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.border,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 14,
                          ),
                        ),
                        icon: Icon(
                          Icons.folder_open,
                          color: AppColors.primaryLight,
                          size: 18,
                        ),
                        label: const Text(
                          'تصفح الجهاز',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.fontSmall,
                          ),
                        ),
                        onPressed: () async {
                          final base64Image =
                              await FilePickerHelper.pickImageAsBase64();
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
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'سعر الشراء',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sellingCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'سعر البيع',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'الكمية في المخزن',
                              labelStyle: TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: TextField(
                          controller: categoryCtrl,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'التصنيف (القسم)',
                            labelStyle: TextStyle(color: AppColors.textGray),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'يباع بالوزن؟',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
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
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'الوحدة لسعر البيع (غرام)',
                              labelStyle: TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: weightIncCtrl,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'خطوة الوزن (+/-)',
                              labelStyle: TextStyle(color: AppColors.textGray),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'إلغاء',
                  style: TextStyle(color: AppColors.textGray),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primarySolid,
                ),
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
                    'weight_unit_grams':
                        int.tryParse(weightUnitCtrl.text) ?? 1000,
                    'weight_increment_step':
                        double.tryParse(weightIncCtrl.text) ?? 100.0,
                  });
                  _loadProducts();
                },
                child: const Text(
                  'حفظ التعديلات',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRestockDialog(ProductModel product) {
    final qtyCtrl = TextEditingController(text: '10');
    final purchasePriceCtrl = TextEditingController(
      text: product.purchasePrice.toStringAsFixed(0),
    );
    final sellingPriceCtrl = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.add_business_outlined,
                color: AppColors.primaryLight,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'توريد وشراء شحنة إضافية: ${product.name}',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppSizes.fontHeader,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'الكمية المضافة للمخزن',
                  labelStyle: TextStyle(color: AppColors.textGray),
                  prefixIcon: Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primaryLight,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: purchasePriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'سعر الشراء للشحنة (تكلفة القطعة)',
                  labelStyle: TextStyle(color: AppColors.textGray),
                  prefixIcon: const Icon(
                    Icons.shopping_cart_checkout,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  helperText:
                      'سعر الشراء الحالي: ${product.purchasePrice.toStringAsFixed(0)} د.ع',
                  helperStyle: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 11,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sellingPriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'سعر البيع للزبون (تحديث السعر)',
                  labelStyle: TextStyle(color: AppColors.textGray),
                  prefixIcon: const Icon(
                    Icons.sell_outlined,
                    color: AppColors.success,
                    size: 20,
                  ),
                  helperText:
                      'سعر البيع الحالي: ${product.sellingPrice.toStringAsFixed(0)} د.ع (يمكن تعديله)',
                  helperStyle: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 11,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: TextStyle(color: AppColors.textGray)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text) ?? 0;
              final pPrice =
                  double.tryParse(purchasePriceCtrl.text) ??
                  product.purchasePrice;
              final sPrice =
                  double.tryParse(sellingPriceCtrl.text) ??
                  product.sellingPrice;
              if (qty > 0) {
                Navigator.pop(ctx);
                await ApiService.restockProduct(
                  product.id,
                  qty,
                  pPrice,
                  sellingPrice: sPrice,
                );
                _loadProducts();
              }
            },
            child: const Text(
              'تأكيد التوريد والأسعار',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.history,
                color: AppColors.primaryLight,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'سجل مشتريات: ${product.name}',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppSizes.fontHeader,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 380,
          child: history.isEmpty
              ? Center(
                  child: Text(
                    'لا توجد سجلات شراء سابقة',
                    style: TextStyle(color: AppColors.textGray),
                  ),
                )
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final h = history[index];
                    final isInitial =
                        h.note.contains('أول') || index == history.length - 1;
                    final qtyStr = (h.quantity % 1 == 0)
                        ? h.quantity.toInt().toString()
                        : h.quantity.toString();
                    final labelText = isInitial
                        ? 'أول عملية شراء (إضافة المنتج)'
                        : (h.note.isNotEmpty ? h.note : 'توريد شحنة إضافية');

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isInitial
                              ? AppColors.success.withOpacity(0.4)
                              : AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isInitial
                                      ? AppColors.stockHighBg
                                      : AppColors.primaryLight.withOpacity(
                                          0.15,
                                        ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isInitial
                                          ? Icons.star
                                          : Icons.inventory_2_outlined,
                                      size: 13,
                                      color: isInitial
                                          ? AppColors.stockHighText
                                          : AppColors.primaryLight,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      labelText,
                                      style: TextStyle(
                                        color: isInitial
                                            ? AppColors.stockHighText
                                            : AppColors.primaryLight,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${h.purchasePrice.toStringAsFixed(0)} د.ع',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.shopping_bag_outlined,
                                    size: 15,
                                    color: AppColors.textGray,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'الكمية: $qtyStr',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: AppColors.textGray,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    h.createdAt,
                                    style: TextStyle(
                                      color: AppColors.textGray,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق', style: TextStyle(color: AppColors.textGray)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProduct(ProductModel product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'تأكيد حذف المنتج',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'هل أنت متأكد من حذف ${product.name}؟',
          style: TextStyle(color: AppColors.textDialog),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
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
    if (_busy || _cart.isEmpty) return;
    _saveDebounce?.cancel();
    setState(() => _busy = true);
    if (_activeTable != null && !await _queueSave()) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    _checkoutKey ??=
        '${ApiService.currentUser?.id}-${DateTime.now().microsecondsSinceEpoch}';
    final success = await ApiService.checkoutSale(
      _cart,
      'نقداً',
      _globalDiscount,
      tableId: _activeTable?['id'],
      checkoutKey: _checkoutKey!,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (success) {
        _activeTable = null;
        _checkoutKey = null;
        _cartNotifier.value = [];
        _cardQuantitiesNotifier.value = {};
        _globalDiscount = 0;
        _customTotalSellingPrice = null;
      }
    });
    _notice(
      success ? 'تم إكمال البيع وتحديث المخزون بنجاح' : ApiService.lastError,
    );
    if (success) {
      await _loadProducts();
      if (mounted) await _loadTables();
    }
  }

  Widget? _buildProductImage(String imageUrl) {
    final source = imageUrl.trim();
    if (source.isEmpty) return null;
    try {
      final ImageProvider provider;
      if (source.startsWith('data:image')) {
        provider = MemoryImage(base64Decode(source.split(',').last));
      } else if (source.startsWith('https://') ||
          source.startsWith('http://')) {
        provider = NetworkImage(source);
      } else {
        return null;
      }
      return InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (ctx) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: 'إغلاق الصورة',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image(
                      image: provider,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) =>
                          const Text('تعذر تحميل الصورة'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: provider,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) => const SizedBox.shrink(),
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildProductCard(
    ProductModel product,
  ) => ValueListenableBuilder<Map<int, double>>(
    key: ValueKey('product-card-${product.id}'),
    valueListenable: _cardQuantitiesNotifier,
    builder: (context, quantities, _) {
      final quantity = quantities[product.id] ?? 0;
      final step = product.isWeight ? product.weightIncrementStep : 1.0;
      final controller = _getController(
        'card_qty_${product.id}',
        _formatQty(quantity),
      );
      if (double.tryParse(controller.text) != quantity)
        controller.text = _formatQty(quantity);
      return Container(
        key: ValueKey('product-${product.id}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: quantity > 0 ? AppColors.primaryLight : AppColors.border,
            width: quantity > 0 ? 2 : 1,
          ),
        ),
        child: _photoCardContent(
          product,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (appPermissions.canManageProducts)
                    PopupMenuButton<String>(
                      tooltip: 'إدارة المنتج',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            _showEditProductDialog(product);
                          case 'restock':
                            _showRestockDialog(product);
                          case 'history':
                            _showRestockHistoryDialog(product);
                          case 'delete':
                            _confirmDeleteProduct(product);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('تعديل المنتج'),
                        ),
                        const PopupMenuItem(
                          value: 'restock',
                          child: Text('توريد المخزون'),
                        ),
                        const PopupMenuItem(
                          value: 'history',
                          child: Text('سجل التوريد'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('حذف المنتج'),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  Text(
                    '${product.sellingPrice.toStringAsFixed(0)} د.ع${product.isWeight ? ' / ${product.weightUnitGrams} غم' : ''}',
                    style: TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'المخزون: ${_formatQty(product.stockQuantity)}${product.isWeight ? ' غم' : ''}',
                    style: TextStyle(
                      color: product.stockQuantity > 5
                          ? AppColors.stockHighText
                          : AppColors.stockLowText,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (appPermissions.canViewPurchasePrice ||
                  appPermissions.canViewProfit)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (appPermissions.canViewPurchasePrice)
                        Text(
                          'شراء: ${product.purchasePrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      if (appPermissions.canViewProfit)
                        Text(
                          'ربح الوحدة: ${product.unitProfit.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: AppColors.stockHighText,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: 'تقليل الكمية',
                    onPressed: quantity > 0
                        ? () => _updateProductQuantity(product, quantity - step)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey('quantity-${product.id}'),
                      controller: controller,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: product.isWeight ? 'الوزن (غم)' : 'الكمية',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (value) {
                        final number = double.tryParse(value);
                        if (number != null)
                          _updateProductQuantity(product, number);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'زيادة الكمية',
                    onPressed: quantity >= product.stockQuantity
                        ? null
                        : () => _updateProductQuantity(
                            product,
                            (quantity + step).clamp(0, product.stockQuantity),
                          ),
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey('add-product-${product.id}'),
                  onPressed: quantity >= product.stockQuantity
                      ? null
                      : () => _updateProductQuantity(
                          product,
                          (quantity + step).clamp(0, product.stockQuantity),
                        ),
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: Text(
                    product.stockQuantity <= 0
                        ? 'نفد المخزون'
                        : quantity >= product.stockQuantity
                        ? 'الكمية المتاحة بالسلة'
                        : 'إضافة للسلة',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _photoCardContent(ProductModel product, Widget body) {
    final image = _buildProductImage(product.imageUrl);
    return image == null ? body : ProductPhotoBody(image: image, body: body);
  }

  final _productSearch = TextEditingController();

  Widget _buildProductsArea() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _productSearch,
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 400),
                    () {
                      if (!mounted) return;
                      _searchQuery = value;
                      _loadProducts();
                    },
                  );
                },
                decoration: InputDecoration(
                  hintText: 'ابحث عن منتج أو تصنيف',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (appPermissions.canManageProducts) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'إضافة منتج',
                onPressed: _showAddProductDialog,
                icon: const Icon(Icons.add),
              ),
            ],
            IconButton(
              tooltip: 'تحديث المنتجات',
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _products.isEmpty
            ? _emptyState(
                Icons.inventory_2_outlined,
                'لا توجد منتجات مطابقة حالياً',
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 300).floor().clamp(
                    1,
                    6,
                  );
                  return SingleChildScrollView(
                    key: const PageStorageKey('pos-products'),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: ProductMasonry(
                      columns: columns,
                      children: _products.map(_buildProductCard).toList(),
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _buildCartArea() => AnimatedBuilder(
    animation: Listenable.merge([_cartNotifier, _globalDiscountNotifier]),
    builder: (context, _) {
      final cost = _cart.fold(0.0, (sum, item) => sum + item.totalPurchaseCost);
      final selling = _cart.fold(
        0.0,
        (sum, item) => sum + item.totalSellingAmount,
      );
      final discount =
          _cart.fold(0.0, (sum, item) => sum + item.totalDiscountAmount) +
          _globalDiscount;
      final total = selling - discount;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _activeTable == null
                        ? 'تفاصيل الطلب والسلة'
                        : 'طلب ${_activeTable!['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _cartNotifier.value = [];
                      _cardQuantitiesNotifier.value = {};
                      _globalDiscount = 0;
                      _customTotalSellingPrice = null;
                      _debouncedSaveTableOrder();
                    },
                    child: const Text(
                      'مسح',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: LayoutBuilder(
              builder: (context, area) => Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      key: const PageStorageKey('pos-cart'),
                      slivers: [
                        if (_cart.isEmpty)
                          SliverToBoxAdapter(
                            child: _emptyState(
                              Icons.shopping_bag_outlined,
                              'السلة فارغة\nاختر منتجات لإضافتها إلى الطلب',
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.all(10),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final item = _cart[index];
                              return CartItemWidget(
                                key: ValueKey('cart-${item.product.id}'),
                                item: item,
                                onUpdate: () {
                                  _cartNotifier.value = List.from(_cart);
                                  _debouncedSaveTableOrder();
                                },
                                onUpdateQuantity: _updateProductQuantity,
                              );
                            }, childCount: _cart.length),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    key: const ValueKey('pinned-cart-summary'),
                    constraints: BoxConstraints(
                      maxHeight: area.maxHeight * .58,
                    ),
                    child: SingleChildScrollView(
                      key: const PageStorageKey('cart-summary-scroll'),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: CartSummaryWidget(
                        totalCostSum: cost,
                        totalSellingSum: selling,
                        totalDiscountSum: discount,
                        totalFinalAmount: total,
                        totalNetProfitSum: total - cost,
                        totalItems: _cart.length,
                        canViewPurchasePrice:
                            appPermissions.canViewPurchasePrice,
                        canViewProfit: appPermissions.canViewProfit,
                        onUpdateTotalSelling: (value) {
                          _updateCartFinalTotal(value);
                          _debouncedSaveTableOrder();
                        },
                        onUpdateTotalDiscount: (value) {
                          _updateCartTotalDiscount(value);
                          _debouncedSaveTableOrder();
                        },
                        onUpdateFinalTotal: (value) {
                          _updateCartFinalTotal(value);
                          _debouncedSaveTableOrder();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('checkout'),
                onPressed: _cart.isEmpty ? null : _completeCheckout,
                icon: const Icon(Icons.check_circle_outline),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'إكمال الطلب • ${total.toStringAsFixed(0)} د.ع',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _sectionTabs(bool compact) =>
      ValueListenableBuilder<List<CartItemModel>>(
        valueListenable: _cartNotifier,
        builder: (context, cart, _) => _panel(
          Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (final section in [
                  (0, Icons.grid_view_rounded, 'المنتجات'),
                  (1, Icons.table_restaurant_outlined, 'الطاولات'),
                  if (compact)
                    (2, Icons.shopping_bag_outlined, 'السلة (${cart.length})'),
                ])
                  Expanded(
                    child: TextButton(
                      key: ValueKey('pos-section-${section.$1}'),
                      onPressed: () => _selectSection(section.$1),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        backgroundColor:
                            (_selectedTabIndex == section.$1 ||
                                !compact &&
                                    _selectedTabIndex == 2 &&
                                    section.$1 == 0)
                            ? AppColors.primaryLight.withValues(alpha: .10)
                            : Colors.transparent,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            section.$2,
                            size: 18,
                            color: AppColors.primaryLight,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              section.$3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1100;
            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.all(compact ? 10 : 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!compact) ...[
                        Text(
                          'المبيعات والطاولات',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إدارة المنتجات والطلبات وحساب الطاولات من مكان واحد',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_activeTable != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _panel(
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.table_restaurant_outlined,
                                    color: AppColors.primaryLight,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'طلب ${_activeTable!['name']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _returnToTables,
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      size: 18,
                                    ),
                                    label: const Text('حفظ ورجوع'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      _sectionTabs(compact),
                      const SizedBox(height: 12),
                      Expanded(
                        child: compact
                            ? IndexedStack(
                                index: _selectedTabIndex,
                                children: [
                                  _panel(_buildProductsArea()),
                                  _panel(_buildTablesGrid()),
                                  _panel(_buildCartArea()),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _panel(
                                      IndexedStack(
                                        index: _selectedTabIndex == 1 ? 1 : 0,
                                        children: [
                                          _buildProductsArea(),
                                          _buildTablesGrid(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 390,
                                    child: _panel(_buildCartArea()),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  Positioned.fill(
                    child: AbsorbPointer(
                      child: ColoredBox(
                        color: AppColors.surface.withValues(alpha: .8),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
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

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _sumSellCtrl = TextEditingController(
      text: widget.totalSellingSum.toStringAsFixed(0),
    );
    _sumDiscCtrl = TextEditingController(
      text: widget.totalDiscountSum.toStringAsFixed(0),
    );
    _sumFinalCtrl = TextEditingController(
      text: widget.totalFinalAmount.toStringAsFixed(0),
    );
    ThemeService.themeModeNotifier.addListener(_onThemeChanged);
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
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
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
                Expanded(
                  child: Text(
                    'المجموع الكلي للطلب',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: AppSizes.fontLarge,
                    ),
                  ),
                ),
                Text(
                  '(${widget.totalItems} منتجات)',
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: AppSizes.fontNormal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Total Selling Display
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'السعر الكلي:',
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: AppSizes.fontNormal,
                  ),
                ),
                Text(
                  '${widget.totalSellingSum.toStringAsFixed(0)} د.ع',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: AppSizes.fontMedium,
                  ),
                ),
              ],
            ),

            if (widget.totalDiscountSum > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    const Text(
                      'الخصم الكلي:',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                    Text(
                      '-${widget.totalDiscountSum.toStringAsFixed(0)} د.ع',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                        fontSize: AppSizes.fontMedium,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'السعر النهائي للطلب:',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: AppSizes.fontNormal,
                  ),
                ),
                Text(
                  '${widget.totalFinalAmount.toStringAsFixed(0)} د.ع',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: AppSizes.fontLarge,
                  ),
                ),
              ],
            ),

            Divider(color: AppColors.border, height: 24),

            // Show Details Button
            Center(
              child: TextButton.icon(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.primaryLight,
                  size: 20,
                ),
                label: Text(
                  _isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
                  style: TextStyle(color: AppColors.primaryLight),
                ),
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
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      'مجموع سعر الشراء:',
                      style: TextStyle(
                        color: AppColors.textGray,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                    Text(
                      '${widget.totalCostSum.toStringAsFixed(0)} (ثابتة)',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Edit Total Selling
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      'سعر البيع الكلي:',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                    onPressed: () => widget.onUpdateTotalSelling(
                      widget.totalSellingSum - 500,
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumSellCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: AppSizes.fontNormal,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
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
                    icon: Icon(
                      Icons.add_circle,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                    onPressed: () => widget.onUpdateTotalSelling(
                      widget.totalSellingSum + 500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Edit Total Discount
              Row(
                children: [
                  const SizedBox(
                    width: 90,
                    child: Text(
                      'الخصم الكلي:',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    onPressed: () => widget.onUpdateTotalDiscount(
                      widget.totalDiscountSum - 250,
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumDiscCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: AppSizes.fontNormal,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
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
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    onPressed: () => widget.onUpdateTotalDiscount(
                      widget.totalDiscountSum + 250,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Edit Final Amount
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      'السعر النهائي:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppSizes.fontNormal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                    onPressed: () => widget.onUpdateFinalTotal(
                      (widget.totalFinalAmount - 250).clamp(0, 9999999),
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _sumFinalCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: AppSizes.fontLarge,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
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
                    icon: Icon(
                      Icons.add_circle,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                    onPressed: () => widget.onUpdateFinalTotal(
                      (widget.totalFinalAmount + 250).clamp(0, 9999999),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (widget.canViewProfit) ...[
                Divider(color: AppColors.border, height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    const Text(
                      'مجموع صافي الربح:',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: AppSizes.fontNormal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.totalNetProfitSum.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: AppSizes.fontLarge,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
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

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _initControllers();
    ThemeService.themeModeNotifier.addListener(_onThemeChanged);
  }

  void _initControllers() {
    String qStr = widget.item.quantity == widget.item.quantity.toInt()
        ? widget.item.quantity.toInt().toString()
        : widget.item.quantity.toString();
    _qtyCtrl = TextEditingController(text: qStr);
    _unitDiscountCtrl = TextEditingController(
      text: widget.item.discount.toStringAsFixed(0),
    );
    _discountCtrl = TextEditingController(
      text: widget.item.totalDiscountAmount.toStringAsFixed(0),
    );
    _totalCtrl = TextEditingController(
      text: widget.item.totalPrice.toStringAsFixed(0),
    );
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
    ThemeService.themeModeNotifier.removeListener(_onThemeChanged);
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
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: AppSizes.fontLarge,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.danger,
                    size: 18,
                  ),
                  onPressed: () =>
                      widget.onUpdateQuantity(widget.item.product, 0),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 1. Quantity Field
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    'الكمية/الوزن:',
                    style: TextStyle(
                      color: AppColors.textGray,
                      fontSize: AppSizes.fontNormal,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle,
                    color: AppColors.danger,
                    size: 20,
                  ),
                  onPressed: () => widget.onUpdateQuantity(
                    widget.item.product,
                    widget.item.quantity -
                        (widget.item.product.isWeight
                            ? widget.item.product.weightIncrementStep
                            : 1.0),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppSizes.fontNormal,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
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
                  icon: const Icon(
                    Icons.add_circle,
                    color: AppColors.success,
                    size: 20,
                  ),
                  onPressed: () => widget.onUpdateQuantity(
                    widget.item.product,
                    widget.item.quantity +
                        (widget.item.product.isWeight
                            ? widget.item.product.weightIncrementStep
                            : 1.0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Total Price Text
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'المبلغ:',
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: AppSizes.fontNormal,
                  ),
                ),
                Text(
                  '${widget.item.totalSellingAmount.toStringAsFixed(0)} د.ع',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: AppSizes.fontMedium,
                  ),
                ),
              ],
            ),

            // Discount Text (if any)
            if (widget.item.totalDiscountAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    const Text(
                      'مجموع الخصم:',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                    Text(
                      '-${widget.item.totalDiscountAmount.toStringAsFixed(0)} د.ع',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                        fontSize: AppSizes.fontMedium,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'السعر النهائي:',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: AppSizes.fontNormal,
                  ),
                ),
                Text(
                  '${widget.item.totalPrice.toStringAsFixed(0)} د.ع',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: AppSizes.fontMedium,
                  ),
                ),
              ],
            ),

            Divider(color: AppColors.border, height: 24),

            // Show Details Button
            Center(
              child: TextButton.icon(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.primaryLight,
                  size: 20,
                ),
                label: Text(
                  _isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
                  style: TextStyle(color: AppColors.primaryLight),
                ),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      'الكمية: ${widget.item.quantity}',
                      style: TextStyle(color: AppColors.textGray),
                    ),
                    if (appPermissions.canViewPurchasePrice)
                      Text(
                        'شراء: ${widget.item.unitPurchasePrice.toStringAsFixed(0)} د.ع',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                    Text(
                      'بيع: ${widget.item.unitSellingPrice.toStringAsFixed(0)} د.ع',
                      style: TextStyle(color: AppColors.primaryLight),
                    ),
                    if (appPermissions.canViewPurchasePrice)
                      Text(
                        'كلفة الشراء: ${widget.item.totalPurchaseCost.toStringAsFixed(0)} د.ع',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                    Text(
                      'الخصم: ${widget.item.totalDiscountAmount.toStringAsFixed(0)} د.ع',
                      style: TextStyle(color: AppColors.warning),
                    ),
                    Text(
                      'الإجمالي: ${widget.item.totalPrice.toStringAsFixed(0)} د.ع',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (appPermissions.canViewProfit)
                      Text(
                        'الربح: ${widget.item.netProfit.toStringAsFixed(0)} د.ع',
                        style: TextStyle(
                          color: AppColors.historyIcon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Unit Discount Field Editable
              Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'خصم الوحدة:',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.remove,
                      color: AppColors.warning,
                      size: 18,
                    ),
                    onPressed: () {
                      widget.item.discount = (widget.item.discount - 100).clamp(
                        0,
                        9999999,
                      );
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
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: AppSizes.fontNormal,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
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
                    icon: const Icon(
                      Icons.add,
                      color: AppColors.warning,
                      size: 18,
                    ),
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
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'الخصم الكلي:',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: AppSizes.fontNormal,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.remove,
                      color: AppColors.warning,
                      size: 18,
                    ),
                    onPressed: () {
                      widget.item.totalDiscountAmount =
                          (widget.item.totalDiscountAmount - 100).clamp(
                            0,
                            9999999,
                          );
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
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: AppSizes.fontNormal,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
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
                    icon: const Icon(
                      Icons.add,
                      color: AppColors.warning,
                      size: 18,
                    ),
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
                  SizedBox(
                    width: 80,
                    child: Text(
                      'السعر النهائي:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppSizes.fontNormal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.remove,
                      color: AppColors.primaryLight,
                      size: 18,
                    ),
                    onPressed: () {
                      widget.item.totalPrice = (widget.item.totalPrice - 250)
                          .clamp(0, 9999999);
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
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: AppSizes.fontNormal,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
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
                    icon: Icon(
                      Icons.add,
                      color: AppColors.primaryLight,
                      size: 18,
                    ),
                    onPressed: () {
                      widget.item.totalPrice += 250;
                      widget.onUpdate();
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
