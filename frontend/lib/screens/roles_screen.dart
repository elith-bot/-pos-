import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/permissions_service.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});
  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  List<Map<String, dynamic>> roles = [];
  Map<String, dynamic> groups = {}, dependencies = {};
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await ApiService.businessRequest('/api/roles');
      if (!mounted) return;
      setState(() {
        roles = List<Map<String, dynamic>>.from(result['roles']);
        ApiService.roleCatalog = roles;
        groups = Map<String, dynamic>.from(result['groups']);
        dependencies = Map<String, dynamic>.from(result['dependencies']);
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
        });
    }
  }

  Future<void> edit([Map<String, dynamic>? role]) async {
    final name = TextEditingController(text: role?['name'] ?? '');
    final editable = groups.values.expand((g) => (g as Map).keys).toSet();
    final selected = Set<String>.from(
      (role?['permissions'] as List? ?? []).where(editable.contains),
    );
    bool busy = false;
    String? message;
    void enable(String key) {
      if (selected.add(key)) {
        for (final dep in dependencies[key] ?? []) {
          enable('$dep');
        }
      }
    }

    void disable(String key) {
      selected.remove(key);
      for (final p in selected.toList()) {
        if ((dependencies[p] as List? ?? []).contains(key)) disable(p);
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !busy,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text(role == null ? 'إنشاء دور جديد' : 'تعديل الدور'),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: name,
                        enabled: !busy,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'اسم الدور',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'اختر الصلاحيات المطلوبة. الصلاحيات المرتبطة تُحدد تلقائياً؛ مثلاً صرف الراتب يحتاج عرض الرواتب. عرض الربح يحتاج عرض التكلفة. الأدوار الجديدة دون المالك والمطور ولا تدير أدواراً بمستواها.',
                      ),
                      Text('الصلاحيات المحددة: ${selected.length}'),
                      for (final group in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            group.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        for (final permission in Map<String, dynamic>.from(
                          group.value,
                        ).entries)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${permission.value}'),
                            value: selected.contains(permission.key),
                            onChanged: busy
                                ? null
                                : (v) => update(() {
                                    if (v == true) {
                                      enable(permission.key);
                                    } else {
                                      disable(permission.key);
                                    }
                                  }),
                          ),
                      ],
                      if (message != null)
                        Text(
                          message!,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                    ],
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
                          if (name.text.trim().isEmpty) {
                            update(() => message = 'اكتب اسم الدور.');
                            return;
                          }
                          update(() => busy = true);
                          try {
                            await ApiService.businessRequest(
                              role == null
                                  ? '/api/roles'
                                  : '/api/roles/${role['id']}',
                              method: role == null ? 'POST' : 'PUT',
                              body: {
                                'name': name.text.trim(),
                                'permissions': selected.toList(),
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await load();
                          } catch (e) {
                            if (ctx.mounted)
                              update(() {
                                message = '$e';
                                busy = false;
                              });
                          }
                        },
                  child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ الدور'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Dialog transition may still reference its controller for one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => name.dispose());
  }

  Future<void> remove(Map<String, dynamic> role) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف دور ${role['name']}؟'),
        content: const Text(
          'لا يمكن حذف دور مرتبط بموظفين. انقلهم إلى دور آخر أولاً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.businessRequest(
        '/api/roles/${role['id']}',
        method: 'DELETE',
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('الأدوار والصلاحيات')),
      body: !appPermissions.has('roles.manage')
          ? const Center(child: Text('إدارة الأدوار متاحة للمالك والمطور.'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: loading ? null : () => edit(),
                    icon: const Icon(Icons.add_moderator),
                    label: const Text('إنشاء دور جديد'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'يمكن تعديل الأدوار الأساسية والمخصصة. تبقى إدارة الأدوار والإعدادات للمالك والمطور لحماية الوصول للإدارة. تعديل الدور ينهي جلسات موظفيه لتطبيق الصلاحيات الجديدة.',
                ),
                if (loading) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                for (final role in roles)
                  Card(
                    child: ListTile(
                      title: Text('${role['name']}'),
                      subtitle: Text(
                        role['builtin'] == true
                            ? 'دور أساسي'
                            : '${(role['permissions'] as List).length} صلاحية',
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'تعديل الدور والصلاحيات',
                            onPressed: () => edit(role),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          if (role['builtin'] != true)
                            IconButton(
                              tooltip: 'حذف الدور',
                              onPressed: () => remove(role),
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}
