import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/permissions_service.dart';
import '../services/theme_service.dart';
import 'auth_screen.dart';
import 'support_screen.dart';
import '../services/system_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = true;
  String? _error;
  int _revision = 0;
  Map<String, dynamic> _settings = {}, _tabs = {}, _presets = {};
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _address = TextEditingController();
  @override
  void initState() {
    super.initState();
    ThemeService.themeModeNotifier.addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    ThemeService.themeModeNotifier.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ApiService.businessRequest('/api/settings');
      if (!mounted) return;
      SystemSettingsService.apply(data);
      setState(() {
        _settings = Map<String, dynamic>.from(data['settings']);
        _settings['tabs'] = Map<String, dynamic>.from(_settings['tabs']);
        _revision = data['revision'];
        _tabs = Map<String, dynamic>.from(data['tabs']);
        _presets = Map<String, dynamic>.from(data['presets']);
        _name.text = _settings['business_name'];
        _phone.text = _settings['business_phone'];
        _address.text = _settings['business_address'];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = {
        ..._settings,
        'business_name': _name.text.trim(),
        'business_phone': _phone.text.trim(),
        'business_address': _address.text.trim(),
      };
      final result = await ApiService.businessRequest(
        '/api/settings',
        method: 'PUT',
        body: {'settings': value, 'revision': _revision},
      );
      if (!mounted) return;
      SystemSettingsService.apply(result);
      setState(() => _revision = result['revision']);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات النشاط')));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          if (appPermissions.canManageSettings) _panel(
            'الدعم والصيانة',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الفحص المحلي والنسخ الاحتياطي متاحان. الاتصال عن بُعد سيُتاح بعد تجهيز خادم الدعم وبموافقتك لكل جلسة.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SupportScreen()),
                  ),
                  icon: const Icon(Icons.headset_mic_outlined),
                  label: const Text('فتح مركز الدعم الفني والصيانة'),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('إعادة تحميل الإعدادات'),
            ),
          ],
          if (appPermissions.canManageSettings && _settings.isNotEmpty) ...[
            _panel(
              'بيانات النشاط',
              Column(
                children: [
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'اسم النشاط'),
                  ),
                  TextField(
                    controller: _phone,
                    enabled: !_busy,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                  ),
                  TextField(
                    controller: _address,
                    enabled: !_busy,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _settings['business_type'],
                    decoration: const InputDecoration(labelText: 'نوع النشاط'),
                    items: _presets.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text('${e.value}'),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _settings['business_type'] = value;
                            _settings['tabs']['tables'] =
                                value == 'restaurant' || value == 'general';
                            if (_settings['tabs']['tables'] == true)
                              _settings['tabs']['sales'] = true;
                          }),
                  ),
                  const Text(
                    'اختيار مطعم يُظهر الطاولات؛ السوبر ماركت والمتجر يخفيانها. يمكن تعديل التبويبات أدناه.',
                  ),
                ],
              ),
            ),
            _panel(
              'إظهار وإخفاء التبويبات',
              Column(
                children: [
                  const Text(
                    'الإعدادات تبقى متاحة دائماً. إخفاء التبويب لا يغيّر صلاحيات الموظفين ولا يحذف البيانات. أكمل طلبات الطاولات المفتوحة قبل إخفائها.',
                  ),
                  for (final tab in _tabs.entries)
                    SwitchListTile(
                      title: Text('${tab.value}'),
                      value: _settings['tabs'][tab.key] == true,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _settings['tabs'][tab.key] = value;
                              if (tab.key == 'sales' && !value)
                                _settings['tabs']['tables'] = false;
                              if (tab.key == 'tables' && value)
                                _settings['tabs']['sales'] = true;
                            }),
                    ),
                ],
              ),
            ),
            _panel(
              'الدخول والأمان',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مدة جلسة الدخول: ${_settings['session_hours']} ساعة'),
                  Slider(
                    value: (_settings['session_hours'] as num).toDouble(),
                    min: 1,
                    max: 72,
                    divisions: 71,
                    label: '${_settings['session_hours']} ساعة',
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _settings['session_hours'] = v.round(),
                          ),
                  ),
                  const Text(
                    'تُطبّق المدة على جلسات الدخول الجديدة. صلاحيات كل موظف تُدار من صفحة الموظفين والأدوار.',
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ إعدادات النظام'),
            ),
          ],
        ],
      ),
    ),
  );
}
