"""Server-enforced sessions and role policy for the POS."""
import hashlib
import secrets
from datetime import datetime, timedelta
from flask import request, jsonify, g
from werkzeug.security import check_password_hash, generate_password_hash
from models import db, User, AuthSession

RANK = {'cashier': 0, 'admin': 1, 'owner': 2, 'developer': 3}
MANAGERS = {'admin', 'owner', 'developer'}
POLICY = {
    'register': MANAGERS, 'get_users': MANAGERS,
    'update_user_role': MANAGERS, 'toggle_user_active': MANAGERS,
    'reset_employee_password': MANAGERS,
    'create_product': MANAGERS, 'update_product': MANAGERS,
    'restock_product': MANAGERS, 'delete_product': MANAGERS,
    'get_restock_history': MANAGERS, 'get_expenses': MANAGERS,
    'create_expense': MANAGERS, 'delete_expense': MANAGERS,
    'update_expense': MANAGERS,
    'get_stats': MANAGERS, 'get_sales': MANAGERS,
    'create_tables': MANAGERS, 'delete_table': MANAGERS,
    'switch_db': {'owner', 'developer'}, 'api_core_action': {'developer'},
    'get_products': set(RANK), 'get_product_by_barcode': set(RANK),
    'create_sale': set(RANK), 'get_tables': set(RANK),
    'get_table_order': set(RANK), 'save_table_order': set(RANK),
    'current_session': set(RANK), 'logout': set(RANK), 'change_password': set(RANK),
}

def failure(message, status=403):
    return jsonify(status='error', message=message), status

def issue_session(user):
    token = secrets.token_urlsafe(32)
    db.session.add(AuthSession(token_hash=hashlib.sha256(token.encode()).hexdigest(),
        user_id=user.id, expires_at=datetime.utcnow() + timedelta(hours=12)))
    db.session.commit()
    return token

def manageable(user, new_role=None):
    actor = g.current_user
    if actor.id == user.id:
        return False
    rank = RANK.get(actor.role, -1)
    return rank > RANK.get(user.role, 99) and (
        new_role is None or rank > RANK.get(new_role, 99))

def revoke(user_id):
    AuthSession.query.filter_by(user_id=user_id).delete()

def install_security(app):
    @app.before_request
    def authenticate():
        if request.method == 'OPTIONS' or request.endpoint in {'health_check', 'login'}:
            return None
        if not request.path.startswith('/api/') or request.endpoint is None:
            return None
        header = request.headers.get('Authorization', '')
        token = header[7:] if header.startswith('Bearer ') else ''
        session = db.session.get(AuthSession, hashlib.sha256(token.encode()).hexdigest()) if token else None
        if not session or session.expires_at <= datetime.utcnow():
            return failure('انتهت الجلسة أو لم تسجل الدخول. سجل الدخول مجدداً.', 401)
        user = db.session.get(User, session.user_id)
        if not user or not user.is_active:
            return failure('الحساب معطل. راجع الإدارة.', 401)
        g.current_user = user
        g.auth_session = session
        if user.role not in POLICY.get(request.endpoint, set()):
            return failure('ليس لديك صلاحية لتنفيذ هذا الإجراء.')
        return None

    @app.after_request
    def redact_costs(response):
        if getattr(g, 'current_user', None) and g.current_user.role == 'cashier' and response.is_json:
            hidden = {'purchase_price', 'unit_purchase_price', 'unit_profit',
                      'total_purchase_cost', 'profit', 'net_profit'}
            def clean(value):
                if isinstance(value, dict):
                    return {k: clean(v) for k, v in value.items() if k not in hidden}
                if isinstance(value, list):
                    return [clean(v) for v in value]
                return value
            response.set_data(app.json.dumps(clean(response.get_json())))
        return response

    @app.get('/api/auth/me')
    def current_session():
        return jsonify(status='success', user=g.current_user.to_dict())

    @app.post('/api/auth/logout')
    def logout():
        db.session.delete(g.auth_session)
        db.session.commit()
        return jsonify(status='success')

    @app.post('/api/auth/password')
    def change_password():
        data = request.get_json() or {}
        user = g.current_user
        if not check_password_hash(user.password_hash, data.get('current_password', '')):
            return failure('كلمة المرور الحالية غير صحيحة.', 400)
        password = data.get('new_password', '')
        if len(password) < 8:
            return failure('كلمة المرور الجديدة يجب أن تكون 8 أحرف على الأقل.', 400)
        user.password_hash = generate_password_hash(password)
        revoke(user.id)
        db.session.commit()
        return jsonify(status='success', message='تم تغيير كلمة المرور. سجل الدخول مجدداً.')

    @app.put('/api/users/<int:user_id>/password')
    def reset_employee_password(user_id):
        user = db.session.get(User, user_id)
        if not user:
            return failure('الموظف غير موجود.', 404)
        if not manageable(user):
            return failure('يمكنك إدارة الموظفين ذوي الأدوار الأدنى فقط.')
        password = (request.get_json() or {}).get('new_password', '')
        if len(password) < 8:
            return failure('كلمة المرور يجب أن تكون 8 أحرف على الأقل.', 400)
        user.password_hash = generate_password_hash(password)
        revoke(user.id)
        db.session.commit()
        return jsonify(status='success')

