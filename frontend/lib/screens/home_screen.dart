import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/item.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  bool _isServerOnline = false;
  String _activeDb = 'sqlite';
  bool _dbConnected = false;
  String? _serverError;

  List<Item> _items = [];
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = ApiService.baseUrl;
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    final health = await ApiService.checkHealth();
    final items = await ApiService.getItems();

    if (mounted) {
      setState(() {
        _isServerOnline = health['server'] == 'online';
        _activeDb = health['db_type'] ?? 'sqlite';
        _dbConnected = health['db_connected'] ?? false;
        _serverError = health['error'];
        _items = items;
        _isLoading = false;
      });
    }
  }

  void _showAddItemDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.add_circle, color: AppColors.primaryLight),
            SizedBox(width: 8),
            Text('إضافة عنصر جديد', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'العنوان (Title)',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'الوصف (Description)',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textGray)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primarySolid,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              if (titleController.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final success = await ApiService.addItem(
                titleController.text.trim(),
                descController.text.trim(),
              );
              if (success) {
                _refreshData();
              }
            },
            child: const Text('إضافة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Item item) {
    final titleController = TextEditingController(text: item.title);
    final descController = TextEditingController(text: item.description);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: AppColors.warning),
            SizedBox(width: 8),
            Text('تعديل العنصر', style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'العنوان',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'الوصف',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textGray)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              if (titleController.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final success = await ApiService.updateItem(
                item.id,
                titleController.text.trim(),
                descController.text.trim(),
              );
              if (success) {
                _refreshData();
              }
            },
            child: const Text('حفظ التعديلات', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Item item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
        content: Text('هل أنت تأكد من حذف العنصر "${item.title}"؟',
            style: const TextStyle(color: AppColors.textDialog)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.textGray)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ApiService.deleteItem(item.id);
              if (success) {
                _refreshData();
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: AppColors.primaryLight),
            SizedBox(width: 8),
            Text('إعدادات الاتصال وقاعدة البيانات',
                style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXLarge)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('رابط السيرفر الباك إند (Backend URL):',
                style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontMedium)),
            const SizedBox(height: 6),
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('التبديل بين قواعد البيانات (SQLAlchemy Engine):',
                style: TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontMedium)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _activeDb == 'sqlite'
                          ? const Color(0xFF0284C7)
                          : AppColors.border,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.storage, color: Colors.white, size: 18),
                    label: const Text('SQLite', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      await ApiService.switchDatabase('sqlite');
                      if (ctx.mounted) Navigator.pop(ctx);
                      _refreshData();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _activeDb == 'mysql'
                          ? const Color(0xFFD97706)
                          : AppColors.border,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.dns, color: Colors.white, size: 18),
                    label: const Text('MySQL', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      await ApiService.switchDatabase('mysql');
                      if (ctx.mounted) Navigator.pop(ctx);
                      _refreshData();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySolid),
            onPressed: () {
              ApiService.baseUrl = _urlController.text.trim();
              Navigator.pop(ctx);
              _refreshData();
            },
            child: const Text('حفظ الإعدادات', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.bolt, color: AppColors.primaryLight),
            SizedBox(width: 8),
            Text(
              'Flutter + Python Flask Template',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppSizes.fontXLarge),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primaryLight),
            tooltip: 'تحديث البيانات',
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.textGray),
            tooltip: 'الإعدادات وقواعد البيانات',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: AppColors.primaryLight,
          child: Column(
            children: [
              // Server & Database Health Status Header Card
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isServerOnline
                        ? [AppColors.surface, const Color(0xFF0F2942)]
                        : [const Color(0xFF331B1B), AppColors.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isServerOnline
                        ? const Color(0xFF0369A1).withOpacity(0.5)
                        : const Color(0xFF991B1B).withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _isServerOnline
                                    ? AppColors.success
                                    : AppColors.danger,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _isServerOnline
                                        ? AppColors.success.withOpacity(0.5)
                                        : AppColors.danger.withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isServerOnline ? 'السيرفر متصل (Flask Server Online)' : 'السيرفر غير متصل (Offline)',
                              style: TextStyle(
                                color: _isServerOnline
                                    ? AppColors.stockHighText
                                    : const Color(0xFFFCA5A5),
                                fontWeight: FontWeight.bold,
                                fontSize: AppSizes.fontLarge,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _activeDb == 'mysql'
                                ? const Color(0xFFD97706).withOpacity(0.2)
                                : const Color(0xFF0284C7).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _activeDb == 'mysql'
                                  ? AppColors.warning
                                  : AppColors.primaryLight,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _activeDb == 'mysql' ? Icons.dns : Icons.storage,
                                size: 14,
                                color: _activeDb == 'mysql'
                                    ? AppColors.warning
                                    : AppColors.primaryLight,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'قاعدة البيانات: ${_activeDb.toUpperCase()}',
                                style: TextStyle(
                                  color: _activeDb == 'mysql'
                                      ? const Color(0xFFFDBA74)
                                      : const Color(0xFF7DD3FC),
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppSizes.fontNormal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_serverError != null && !_dbConnected) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.stockLowBg.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'تنبيه: $_serverError',
                          style: const TextStyle(color: AppColors.stockLowText, fontSize: AppSizes.fontNormal),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Action Toolbar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'قائمة العناصر التجريبية (${_items.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: AppSizes.fontHeader,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primarySolid,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add, color: Colors.white, size: 18),
                      label: const Text('إضافة عنصر', style: TextStyle(color: Colors.white)),
                      onPressed: _showAddItemDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Content Area
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primaryLight),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 64, color: Colors.white.withOpacity(0.3)),
                                const SizedBox(height: 12),
                                Text(
                                  _isServerOnline
                                      ? 'لا توجد عناصر حالياً. اضغط "إضافة عنصر" للبدء.'
                                      : 'يرجى تشغيل سيرفر Python Flask للاتصال!',
                                  style: const TextStyle(color: AppColors.textGray, fontSize: AppSizes.fontLarge),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return Card(
                                color: AppColors.surface,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                      color: AppColors.border.withOpacity(0.5)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '#${item.id}',
                                          style: const TextStyle(
                                            color: AppColors.primaryLight,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: AppSizes.fontHeader,
                                              ),
                                            ),
                                            if (item.description.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                item.description,
                                                style: const TextStyle(
                                                  color: AppColors.textGray,
                                                  fontSize: AppSizes.fontMedium,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 6),
                                            Text(
                                              'تاريخ الإنشاء: ${item.createdAt}',
                                              style: const TextStyle(
                                                color: AppColors.textHint,
                                                fontSize: AppSizes.fontSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit,
                                                color: AppColors.warning, size: 20),
                                            onPressed: () => _showEditDialog(item),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: AppColors.danger, size: 20),
                                            onPressed: () => _confirmDelete(item),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
