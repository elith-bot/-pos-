import json
import uuid
from flask import request, jsonify, g
from sqlalchemy.exc import IntegrityError
from models import db, CustomRole, User
from security import failure, revoke
from role_access import GROUPS, DEPENDENCIES, BUILTINS, RANKS, DEFAULTS, permissions_for, normalize_permissions, role_descriptors, role_rank

def install_roles(app):
    @app.get('/api/roles')
    def roles_catalog():
        roles = role_descriptors()
        for role in roles:
            role['permissions'] = sorted(permissions_for(role['id']))
        return jsonify(roles=roles, groups=GROUPS, dependencies={k: sorted(v) for k,v in DEPENDENCIES.items()})

    @app.route('/api/roles', methods=['POST'], defaults={'role_id': None})
    @app.route('/api/roles/<role_id>', methods=['PUT','DELETE'])
    def manage_roles(role_id):
        role = db.session.get(CustomRole, role_id) if role_id else None
        builtin = role_id in BUILTINS
        if role_id and not role and not builtin: return failure('الدور غير موجود.',404)
        if builtin and (role_rank(g.current_user.role) < RANKS[role_id] or (role_id == 'developer' and g.current_user.role != 'developer')):
            return failure('لا يمكنك تعديل دور أعلى من دورك.')
        if request.method == 'DELETE':
            if builtin: return failure('يمكن تعديل الدور الأساسي ولكن لا يمكن حذفه.',400)
            if User.query.filter_by(role=role_id).first(): return failure('انقل الموظفين إلى دور آخر قبل حذف هذا الدور.',409)
            db.session.delete(role); db.session.commit()
            return jsonify(status='success')
        try:
            data = request.get_json() or {}
            name = str(data.get('name','')).strip()
            if not name or len(name)>80: raise ValueError('اكتب اسم الدور من 1 إلى 80 حرفاً.')
            permissions = normalize_permissions(data.get('permissions',[]))
            ceiling = DEFAULTS[g.current_user.role] if builtin and role_id == g.current_user.role else permissions_for(g.current_user.role)
            if not permissions <= ceiling: return failure('لا يمكنك منح صلاحية لا تملكها.')
            if not role:
                role = CustomRole(id=role_id if builtin else 'role_'+uuid.uuid4().hex[:12], name=name)
                db.session.add(role)
            role.name, role.permissions_json = name, json.dumps(sorted(permissions))
            for user in User.query.filter_by(role=role.id).all(): revoke(user.id)
            db.session.commit()
            return jsonify(status='success', role=dict(id=role.id,name=name,permissions=sorted(permissions))), 201 if role_id is None else 200
        except (ValueError, TypeError) as error:
            db.session.rollback(); return failure(str(error),400)
        except IntegrityError:
            db.session.rollback(); return failure('اسم الدور مستخدم مسبقاً.',409)
