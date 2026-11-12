"""Explicit capabilities shared by API authorization and role editor."""
import json
from flask import g
from models import db, CustomRole

BUILTINS = {'cashier': 'كاشير', 'admin': 'مدير', 'owner': 'مالك', 'developer': 'مطور'}
RANKS = {'cashier': 0, 'admin': 1, 'owner': 2, 'developer': 3}
GROUPS = {
 'المنتجات والمخزون': {'products.view':'عرض المنتجات', 'products.create':'إضافة منتج', 'products.edit':'تعديل منتج', 'products.delete':'حذف منتج', 'products.restock':'توريد المخزون', 'stock.history':'عرض سجل التوريد'},
 'المبيعات والطاولات': {'sales.create':'إكمال البيع', 'sales.discount':'تطبيق الخصومات وتعديل المجاميع', 'sales.price':'تغيير سعر البيع', 'sales.view_all':'عرض طلبات جميع الموظفين', 'tables.view':'عرض الطاولات', 'tables.edit':'حفظ وتعديل طلب الطاولة', 'tables.create':'إضافة طاولات', 'tables.delete':'حذف طاولة'},
 'التقارير والتصدير': {'reports.view':'عرض الإحصائيات', 'financial.costs':'عرض أسعار الشراء والتكاليف', 'financial.profit':'عرض الأرباح والخسائر', 'exports.reports':'تصدير الإحصائيات', 'exports.orders':'تصدير الطلبات', 'exports.cart':'تصدير السلة'},
 'المصاريف': {'expenses.view':'عرض المصاريف', 'expenses.create':'إضافة مصروف', 'expenses.edit':'تعديل مصروف', 'expenses.delete':'حذف مصروف', 'fixed.view':'عرض الالتزامات الثابتة', 'fixed.edit':'إضافة وتعديل الالتزامات', 'fixed.pay':'دفع الالتزامات الثابتة'},
 'الحسابات والموظفون': {'employees.view':'عرض حسابات الموظفين', 'employees.create':'إنشاء حساب موظف', 'employees.roles':'تغيير دور الموظف', 'employees.password':'إعادة تعيين كلمة المرور', 'employees.status':'تفعيل وتعطيل الحساب'},
 'الموارد البشرية': {'hr.view':'عرض ملفات الموظفين والعقود', 'hr.edit':'إضافة وتعديل ملفات الموظفين والعقود', 'attendance.view':'عرض الحضور والإجازات', 'attendance.edit':'تسجيل وتعديل الحضور والإجازات', 'payroll.view':'عرض الرواتب', 'payroll.prepare':'إعداد الرواتب والمكافآت والخصومات', 'payroll.pay':'صرف الرواتب'},
}
CAPABILITIES = {key: label for group in GROUPS.values() for key, label in group.items()}
BASE = {'products.view','sales.create','sales.discount','sales.price','tables.view','tables.edit','exports.orders','exports.cart'}
OWNER_ONLY = {'hr.view','hr.edit','attendance.view','attendance.edit','payroll.view','payroll.prepare','payroll.pay','fixed.view','fixed.edit','fixed.pay'}
DEFAULTS = {'cashier': BASE, 'admin': set(CAPABILITIES)-OWNER_ONLY,
            'owner': set(CAPABILITIES)|{'roles.manage','settings.manage'},
            'developer': set(CAPABILITIES)|{'roles.manage','settings.manage','system.core'}}
DEPENDENCIES = {
 'products.create': {'products.view'}, 'products.edit': {'products.view'}, 'products.delete': {'products.view'}, 'products.restock': {'products.view','stock.history','financial.costs'},
 'sales.create': {'products.view'}, 'sales.discount': {'products.view'}, 'sales.price': {'products.view'},
 'tables.edit': {'tables.view','products.view'}, 'tables.create': {'tables.view'}, 'tables.delete': {'tables.view'},
 'reports.view': {'sales.view_all'}, 'exports.reports': {'reports.view','sales.view_all'},
 'exports.cart': {'products.view'}, 'expenses.create': {'expenses.view'}, 'expenses.edit': {'expenses.view'}, 'expenses.delete': {'expenses.view'},
 'employees.create': {'employees.view'}, 'employees.roles': {'employees.view'}, 'employees.password': {'employees.view'}, 'employees.status': {'employees.view'},
 'hr.edit': {'hr.view'}, 'attendance.view': {'hr.view'}, 'attendance.edit': {'hr.view','attendance.view'},
 'payroll.view': {'hr.view'}, 'payroll.prepare': {'hr.view','payroll.view','attendance.view'}, 'payroll.pay': {'hr.view','payroll.view'},
 'fixed.edit': {'fixed.view'}, 'fixed.pay': {'fixed.view'},
 # Profit combined with revenue reveals cost; disclose that dependency explicitly.
 'financial.profit': {'financial.costs'},
}

def permissions_for(role):
    row = db.session.get(CustomRole, role)
    if row:
        return (set(json.loads(row.permissions_json)) & set(CAPABILITIES)) | (set(DEFAULTS.get(role, set())) - set(CAPABILITIES))
    return set(DEFAULTS.get(role, set()))

def role_rank(role):
    return RANKS[role] if role in RANKS else 1 if db.session.get(CustomRole, role) else 99

def role_label(role):
    row = db.session.get(CustomRole, role)
    return row.name if row else BUILTINS.get(role, 'دور غير موجود')

def role_exists(role):
    return isinstance(role, str) and (role in BUILTINS or db.session.get(CustomRole, role) is not None)

def has_permission(key, user=None):
    user = user or getattr(g, 'current_user', None)
    return bool(user and user.is_active and key in permissions_for(user.role))

def role_descriptors():
    return [dict(id=k, name=role_label(k), rank=RANKS[k], builtin=True) for k in BUILTINS] + [
        dict(id=r.id, name=r.name, rank=1, builtin=False) for r in CustomRole.query.order_by(CustomRole.name).all() if r.id not in BUILTINS]

def normalize_permissions(values):
    if not isinstance(values, list) or any(not isinstance(v,str) or v not in CAPABILITIES for v in values):
        raise ValueError('توجد صلاحية غير معروفة أو غير قابلة للتفويض.')
    selected = set(values)
    while True:
        expanded = selected | set().union(*(DEPENDENCIES.get(v,set()) for v in selected))
        if expanded == selected: return selected
        selected = expanded

ENDPOINTS = {
 'register':'employees.create','get_users':'employees.view','update_user_role':'employees.roles','toggle_user_active':'employees.status','reset_employee_password':'employees.password',
 'get_products':'products.view','get_product_by_barcode':'products.view','create_product':'products.create','update_product':'products.edit','delete_product':'products.delete','restock_product':'products.restock','get_restock_history':'stock.history',
 'create_sale':'sales.create','get_sales':'sales.view_all','get_stats':'reports.view',
 'get_tables':'tables.view','get_table_order':'tables.view','save_table_order':'tables.edit','create_tables':'tables.create','delete_table':'tables.delete',
 'get_expenses':'expenses.view','create_expense':'expenses.create','update_expense':'expenses.edit','delete_expense':'expenses.delete',
 'hr_staff':{'GET':'hr.view','POST':'hr.edit'},'hr_update_staff':'hr.edit',
 'hr_attendance':{'GET':'attendance.view','POST':'attendance.edit'},'hr_payroll':{'GET':'payroll.view','POST':'payroll.prepare'},'hr_payroll_preview':'payroll.prepare','hr_payroll_pay':'payroll.pay',
 'fixed_expenses':{'GET':'fixed.view','POST':'fixed.edit'},'fixed_expense_update':'fixed.edit','fixed_expense_pay':'fixed.pay',
 'export_report':'exports.reports','export_sale':'exports.orders','export_cart':'exports.cart',
 'switch_db':'settings.manage','api_core_action':'system.core',
}

def allowed_endpoint(endpoint, method):
    if endpoint == 'system_settings': return method == 'GET' or has_permission('settings.manage')
    if endpoint and endpoint.startswith('remote_support.'):
        return has_permission('settings.manage')
    if endpoint in {'current_session','logout','change_password','my_contract','roles_catalog'}: return True
    if endpoint == 'manage_roles': return has_permission('roles.manage')
    permission = ENDPOINTS.get(endpoint)
    if isinstance(permission,dict): permission = permission.get(method)
    return bool(permission and has_permission(permission))
