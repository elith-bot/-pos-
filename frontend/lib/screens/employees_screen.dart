import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';
import '../services/theme_service.dart';
import '../widgets/section_tabs.dart';
import 'hr_screen.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesHubState();
}

class _EmployeesHubState extends State<EmployeesScreen> {
  int section = 0;
  @override
  Widget build(BuildContext context) {
    if (!appPermissions.canManageEmployees)
      return const Center(child: Text('هذه الصفحة متاحة للإدارة فقط.'));
    if (!appPermissions.canManageHR) return const AccountsScreen();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SectionTabs(
            labels: const ['الموارد البشرية', 'حسابات الدخول والصلاحيات'],
            selected: section,
            onSelected: (value) => setState(() => section = value),
          ),
        ),
        Expanded(
          child: section == 0 ? const HrScreen() : const AccountsScreen(),
        ),
      ],
    );
  }
}

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<AccountsScreen> {
  final _search = TextEditingController();
  List<UserModel> _users = [];
  bool _loading = true;
  String? _error;
  String _role = '', _status = '';
  final Set<int> _busy = {};
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
    _search.dispose();
    ThemeService.themeModeNotifier.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    if (!appPermissions.canManageEmployees) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ApiService.getUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = ApiService.lastError;
          _loading = false;
        });
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _roleDialog(UserModel user) async {
    if (!appPermissions.canManage(user)) return;
    var role = user.role;
    var busy = false;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text('صلاحيات ${user.fullName}'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تغيير الدور ينهي جلسات الموظف الحالية، ويُطبّق بعد تسجيل دخوله مجدداً.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الدور',
                      border: OutlineInputBorder(),
                    ),
                    items: appPermissions.assignableRoles
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(PermissionsService.roles[r]!),
                          ),
                        )
                        .toList(),
                    onChanged: busy ? null : (v) => update(() => role = v!),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: busy || role == user.role
                    ? null
                    : () async {
                        update(() {
                          busy = true;
                          error = null;
                        });
                        final ok = await ApiService.updateUserRole(
                          user.id,
                          role,
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
                child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ الصلاحيات'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && saved == true) {
      _message('تم تحديث الصلاحيات');
      await _load();
    }
  }

  Future<void> _toggle(UserModel user) async {
    if (!appPermissions.canManage(user) || _busy.contains(user.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          user.isActive ? 'تعطيل حساب الموظف؟' : 'تفعيل حساب الموظف؟',
        ),
        content: Text(
          user.isActive
              ? 'سيُمنع ${user.fullName} من الدخول وتنتهي جلساته، وتبقى عملياته السابقة محفوظة.'
              : 'سيتمكن ${user.fullName} من الدخول مجدداً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy.add(user.id));
    final ok = await ApiService.toggleUserActive(user.id);
    if (!mounted) return;
    setState(() => _busy.remove(user.id));
    _message(ok ? 'تم تحديث حالة الحساب' : ApiService.lastError);
    if (ok) await _load();
  }

  Future<void> _credentials([UserModel? user]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmployeeForm(user: user),
    );
    if (mounted && saved == true) {
      _message(
        user == null
            ? 'تمت إضافة الموظف بدور كاشير'
            : 'تم تغيير كلمة المرور وإنهاء الجلسات السابقة',
      );
      await _load();
    }
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  @override
  Widget build(BuildContext context) {
    if (!appPermissions.canManageEmployees)
      return const Center(child: Text('هذه الصفحة متاحة للإدارة فقط.'));
    final users = _users
        .where(
          (u) =>
              (_role.isEmpty || u.role == _role) &&
              (_status.isEmpty || u.isActive == (_status == 'active')) &&
              '${u.fullName} ${u.username}'.toLowerCase().contains(
                _search.text.trim().toLowerCase(),
              ),
        )
        .toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'حسابات الدخول والصلاحيات',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  FilledButton.icon(
                    onPressed: () => _credentials(),
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('إضافة حساب دخول'),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    tooltip: 'تحديث',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _panel(Text('الموظفون: ${_users.length}')),
                  _panel(
                    Text('نشطون: ${_users.where((u) => u.isActive).length}'),
                  ),
                  _panel(
                    Text('معطلون: ${_users.where((u) => !u.isActive).length}'),
                  ),
                  _panel(
                    Text('دورك: ${ApiService.currentUser?.roleArabic ?? ''}'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _panel(
                LayoutBuilder(
                  builder: (context, c) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: c.maxWidth < 650 ? c.maxWidth : 300,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'الاسم أو اسم المستخدم',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth < 650 ? c.maxWidth : 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _role,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'الدور',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('كل الأدوار'),
                            ),
                            ...PermissionsService.roles.entries.map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _role = v!),
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth < 650 ? c.maxWidth : 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _status,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'حالة الحساب',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '',
                              child: Text('كل الحالات'),
                            ),
                            DropdownMenuItem(
                              value: 'active',
                              child: Text('نشط'),
                            ),
                            DropdownMenuItem(
                              value: 'inactive',
                              child: Text('معطل'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _status = v!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _panel(
                const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('ما الذي يسمح به كل دور؟'),
                  children: [
                    ListTile(
                      title: Text('الكاشير'),
                      subtitle: Text(
                        'المبيعات والطاولات وتعديل المظهر وكلمة مروره. أسعار الشراء والأرباح مخفية.',
                      ),
                    ),
                    ListTile(
                      title: Text('المدير'),
                      subtitle: Text(
                        'المخزون والمصاريف والتقارير، وإدارة حسابات الكاشير.',
                      ),
                    ),
                    ListTile(
                      title: Text('المالك'),
                      subtitle: Text(
                        'صلاحيات المدير، وإدارة المديرين وإعدادات الاتصال وقاعدة البيانات.',
                      ),
                    ),
                    ListTile(
                      title: Text('المطور'),
                      subtitle: Text(
                        'صلاحيات المالك وإدارة حسابات المالك. لا يمكن تعديل الحساب الشخصي من صفحة الموظفين.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                _panel(
                  Column(
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              if (!_loading && _error == null && users.isEmpty)
                _panel(const Text('لا يوجد موظفون يطابقون البحث.')),
              ...users.map(
                (u) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              u.fullName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Chip(label: Text(u.roleArabic)),
                            Chip(label: Text(u.isActive ? 'نشط' : 'معطل')),
                            if (u.id == ApiService.currentUser?.id)
                              const Chip(label: Text('حسابك')),
                          ],
                        ),
                        Text('${u.username} • تاريخ التسجيل: ${u.createdAt}'),
                        const SizedBox(height: 12),
                        if (appPermissions.canManage(u))
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy.contains(u.id)
                                    ? null
                                    : () => _roleDialog(u),
                                icon: const Icon(Icons.shield_outlined),
                                label: const Text('تعديل الصلاحيات'),
                              ),
                              TextButton.icon(
                                onPressed: _busy.contains(u.id)
                                    ? null
                                    : () => _credentials(u),
                                icon: const Icon(Icons.lock_reset),
                                label: const Text('كلمة المرور'),
                              ),
                              TextButton.icon(
                                onPressed: _busy.contains(u.id)
                                    ? null
                                    : () => _toggle(u),
                                icon: Icon(
                                  u.isActive
                                      ? Icons.block
                                      : Icons.check_circle_outline,
                                ),
                                label: Text(
                                  u.isActive ? 'تعطيل الحساب' : 'تفعيل الحساب',
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            'يمكنك إدارة الأدوار الأدنى من دورك فقط.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeForm extends StatefulWidget {
  final UserModel? user;
  const _EmployeeForm({this.user});
  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = widget.user == null
        ? (await ApiService.register(
                _username.text.trim(),
                _password.text,
                _name.text.trim(),
              ))['status'] ==
              'success'
        : await ApiService.resetEmployeePassword(
            widget.user!.id,
            _password.text,
          );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = ApiService.lastError;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          widget.user == null
              ? 'إضافة موظف'
              : 'كلمة مرور ${widget.user!.fullName}',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.user == null) ...[
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل',
                      ),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'الاسم مطلوب' : null,
                    ),
                    TextFormField(
                      controller: _username,
                      enabled: !_busy,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                      ),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'اسم المستخدم مطلوب' : null,
                    ),
                  ],
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور (8 أحرف على الأقل)',
                    ),
                    validator: (v) =>
                        v!.length < 8 ? 'استخدم 8 أحرف على الأقل' : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.user == null
                        ? 'يُنشأ الحساب بدور كاشير، ويمكن تعديل دوره من القائمة.'
                        : 'سيحتاج الموظف إلى تسجيل الدخول بكلمة المرور الجديدة.',
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'جارٍ الحفظ…' : 'حفظ'),
          ),
        ],
      ),
    ),
  );
}
