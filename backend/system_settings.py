"""Shared, validated settings used by the POS and customer edition builder."""
import copy
import json
from flask import jsonify, request
from sqlalchemy.exc import IntegrityError
from models import db, ActiveOrder, ActiveOrderItem
from security import failure

DEFAULTS = {
    'business_name': 'نظام الكاشير والمبيعات', 'business_phone': '', 'business_address': '',
    'business_type': 'general',
    'tabs': {'sales': True, 'tables': True, 'expenses': True, 'analytics': True, 'employees': True},
    'session_hours': 12,
}
TAB_LABELS = {'sales':'المبيعات', 'tables':'الطاولات', 'expenses':'المصاريف', 'analytics':'الإحصائيات', 'employees':'الموظفون'}
PRESETS = {'general': 'نشاط عام', 'restaurant': 'مطعم أو مقهى', 'supermarket': 'سوبر ماركت', 'retail': 'متجر تجزئة'}


class SystemSettings(db.Model):
    __tablename__ = 'system_settings'
    id = db.Column(db.Integer, primary_key=True)
    value = db.Column(db.Text, nullable=False)
    revision = db.Column(db.Integer, nullable=False, default=1)


def preset(name):
    if name not in PRESETS:
        raise ValueError('نوع النشاط غير معروف.')
    value = copy.deepcopy(DEFAULTS)
    value['business_type'] = name
    value['tabs']['tables'] = name in {'general', 'restaurant'}
    return value


def validate_settings(value):
    if not isinstance(value, dict) or set(value) - set(DEFAULTS):
        raise ValueError('توجد إعدادات غير معروفة.')
    result = copy.deepcopy(DEFAULTS)
    result.update(value)
    for key, limit in [('business_name', 120), ('business_phone', 40), ('business_address', 300)]:
        if not isinstance(result[key], str) or len(result[key].strip()) > limit:
            raise ValueError('بيانات النشاط أطول من الحد المسموح أو غير صالحة.')
        result[key] = result[key].strip()
    if not result['business_name'] or result['business_type'] not in PRESETS:
        raise ValueError('اسم النشاط ونوعه مطلوبان.')
    tabs = result['tabs']
    if not isinstance(tabs, dict) or set(tabs) != set(TAB_LABELS) or any(type(v) is not bool for v in tabs.values()):
        raise ValueError('إعدادات التبويبات غير صالحة.')
    if tabs['tables'] and not tabs['sales']:
        raise ValueError('أظهر تبويب المبيعات لاستخدام الطاولات.')
    if type(result['session_hours']) is not int or not 1 <= result['session_hours'] <= 72:
        raise ValueError('مدة الجلسة يجب أن تكون من 1 إلى 72 ساعة.')
    return result


def get_settings():
    row = db.session.get(SystemSettings, 1)
    return validate_settings(json.loads(row.value)) if row else copy.deepcopy(DEFAULTS)


def install_settings(app):
    @app.route('/api/settings', methods=['GET', 'PUT'])
    def system_settings():
        row = db.session.get(SystemSettings, 1)
        if request.method == 'GET':
            return jsonify(settings=get_settings(), revision=row.revision if row else 0, presets=PRESETS, tabs=TAB_LABELS)
        try:
            data = request.get_json() or {}
            value = validate_settings(data.get('settings'))
            # Compare-and-swap also protects simultaneous editors on different terminals.
            expected = data.get('revision')
            if type(expected) is not int or expected != (row.revision if row else 0):
                return failure('تغيرت الإعدادات بجهاز آخر. أعد تحميلها قبل الحفظ.', 409)
            if not value['tabs']['tables'] and ActiveOrder.query.join(ActiveOrderItem).filter(ActiveOrder.table_id.isnot(None)).first():
                return failure('أكمل طلبات الطاولات المفتوحة قبل إخفائها.', 409)
            if row:
                changed = SystemSettings.query.filter_by(id=1, revision=expected).update(
                    {'value': json.dumps(value), 'revision': expected + 1})
                if changed != 1:
                    db.session.rollback()
                    return failure('تغيرت الإعدادات. أعد تحميلها.', 409)
            else:
                db.session.add(SystemSettings(id=1, value=json.dumps(value), revision=1))
            db.session.commit()
            return jsonify(settings=value, revision=expected + 1)
        except (ValueError, TypeError) as error:
            db.session.rollback()
            return failure(str(error), 400)
        except IntegrityError:
            db.session.rollback()
            return failure('تغيرت الإعدادات. أعد تحميلها قبل الحفظ.', 409)
