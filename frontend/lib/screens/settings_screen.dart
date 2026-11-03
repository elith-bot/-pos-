import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/permissions_service.dart';
import '../services/theme_service.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  Map<String, dynamic> _health = {};
  String? _pendingDb;
  @override
  void initState() {
    super.initState();
    _url.text = ApiService.baseUrl;
    ThemeService.themeModeNotifier.addListener(_changed);
    _check();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _url.dispose();
    ThemeService.themeModeNotifier.removeListener(_changed);
    super.dispose();
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final h = await ApiService.checkHealth();
    if (mounted)
      setState(() {
        _health = h;
        _busy = false;
      });
  }

  Future<void> _server() async {
    final raw = _url.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      _message('أدخل عنوان السيرفر مثل http://127.0.0.1:5000');
      return;
    }
    setState(() => _busy = true);
    final health = await ApiService.checkHealth(url: raw);
    if (!mounted) return;
    setState(() => _busy = false);
    if (health['server'] != 'online' || health['db_connected'] != true) {
      _message(
        'تعذر الاتصال بالسيرفر وقاعدة بياناته. لم يتغير العنوان الحالي.',
      );
      return;
    }
    if (raw == ApiService.baseUrl) {
      _message('الاتصال يعمل');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير السيرفر؟'),
        content: const Text(
          'سيتم تسجيل الخروج للاتصال بالسيرفر الجديد. أكمل سلة البيع المباشر قبل المتابعة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تغيير الاتصال'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await ApiService.logout();
    await SessionService.clearSession();
    ApiService.baseUrl = raw;
    SessionService.saveServerUrl(raw);
    if (mounted)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
  }

  Future<void> _database(String type) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ اختيار قاعدة البيانات؟'),
        content: Text(
          'سيتم اختيار $type عند إعادة تشغيل السيرفر. لا يتم نقل المنتجات والمبيعات تلقائياً بين القواعد. تأكد من تجهيز القاعدة المطلوبة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ الاختيار'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await ApiService.switchDatabase(type);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _pendingDb = type;
    });
    _message(
      ok ? 'تم حفظ الاختيار. أعد تشغيل السيرفر لتطبيقه.' : ApiService.lastError,
    );
  }

  Future<void> _password() async {
    final old = TextEditingController(),
        next = TextEditingController(),
        confirm = TextEditingController();
    final key = GlobalKey<FormState>();
    bool busy = false;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('تغيير كلمة المرور'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: key,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: old,
                        obscureText: true,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور الحالية',
                        ),
                        validator: (v) => v!.isEmpty ? 'مطلوبة' : null,
                      ),
                      TextFormField(
                        controller: next,
                        obscureText: true,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'الجديدة (8 أحرف على الأقل)',
                        ),
                        validator: (v) =>
                            v!.length < 8 ? 'استخدم 8 أحرف على الأقل' : null,
                      ),
                      TextFormField(
                        controller: confirm,
                        obscureText: true,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور',
                        ),
                        validator: (v) => v != next.text
                            ? 'كلمتا المرور غير متطابقتين'
                            : null,
                      ),
                      if (error != null)
                        Text(
                          error!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!key.currentState!.validate()) return;
                        update(() => busy = true);
                        final ok = await ApiService.changePassword(
                          old.text,
                          next.text,
                        );
                        if (!ctx.mounted) return;
                        if (ok) {
                          Navigator.pop(ctx, true);
                        } else {
                          update(() {
                            busy = false;
                            error = ApiService.lastError;
                          });
                        }
                      },
                child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) {
      ApiService.authToken = null;
      ApiService.currentUser = null;
      await SessionService.clearSession();
      if (mounted)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (_) => false,
        );
    }
  }

  Widget _panel(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (MediaQuery.sizeOf(context).width < 700) {
            return Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: PageStorageKey('settings-$title'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                maintainState: true,
                title: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: [child],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          );
        },
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'الإعدادات',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _panel(
            'المظهر',
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('الوضع الفاتح'),
                  avatar: const Icon(Icons.light_mode_outlined),
                  selected: !ThemeService.isDark,
                  onSelected: (_) => ThemeService.setTheme(ThemeMode.light),
                ),
                ChoiceChip(
                  label: const Text('الوضع الداكن'),
                  avatar: const Icon(Icons.dark_mode_outlined),
                  selected: ThemeService.isDark,
                  onSelected: (_) => ThemeService.setTheme(ThemeMode.dark),
                ),
              ],
            ),
          ),
          _panel(
            'حسابك',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ApiService.currentUser?.fullName ?? ''} • ${ApiService.currentUser?.roleArabic ?? ''}',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _password,
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('تغيير كلمة المرور'),
                ),
              ],
            ),
          ),
          _panel(
            'حالة الاتصال',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy)
                  const LinearProgressIndicator()
                else
                  Text(
                    _health['db_connected'] == true
                        ? 'السيرفر وقاعدة البيانات متصلان'
                        : 'الاتصال غير متاح',
                    style: TextStyle(
                      color: _health['db_connected'] == true
                          ? AppColors.stockHighText
                          : AppColors.danger,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'قاعدة البيانات الفعلية: ${_health['db_type'] ?? 'غير معروفة'}',
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _check,
                  icon: const Icon(Icons.refresh),
                  label: const Text('فحص الاتصال'),
                ),
              ],
            ),
          ),
          if (appPermissions.canManageSettings) ...[
            _panel(
              'اتصال السيرفر',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _url,
                    enabled: !_busy,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'عنوان السيرفر',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _server,
                    icon: const Icon(Icons.link),
                    label: const Text('فحص وحفظ الاتصال'),
                  ),
                ],
              ),
            ),
            _panel(
              'قاعدة البيانات',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'يُطبَّق الاختيار بعد إعادة تشغيل السيرفر، ولا ينقل البيانات بين القواعد.',
                  ),
                  if (_pendingDb != null)
                    Text(
                      'بانتظار إعادة التشغيل: $_pendingDb',
                      style: TextStyle(color: AppColors.primaryLight),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final type in ['sqlite', 'mysql'])
                        OutlinedButton(
                          onPressed: _busy || _health['db_type'] == type
                              ? null
                              : () => _database(type),
                          child: Text(type.toUpperCase()),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
