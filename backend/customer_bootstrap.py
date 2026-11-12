"""Apply signed customer defaults exactly once, never replace an existing database."""
import json
from models import db, User, CustomRole
from system_settings import SystemSettings, validate_settings
from role_access import normalize_permissions, BUILTINS


def bootstrap_customer(deployment):
    if User.query.first():
        return
    settings = validate_settings(deployment['settings'])
    owner = deployment['owner']
    if not owner['phone'] or not owner['password_hash'].startswith('scrypt:'):
        raise ValueError('Invalid customer owner credentials')
    for descriptor in deployment.get('roles', []):
        role_id = descriptor['id']
        if role_id not in BUILTINS and not role_id.startswith('role_'):
            raise ValueError('Invalid role id')
        permissions = normalize_permissions(descriptor['permissions'])
        db.session.add(CustomRole(id=role_id, name=descriptor['name'], permissions_json=json.dumps(sorted(permissions))))
    db.session.add(User(username=owner['phone'], full_name=owner['name'], role='owner',
                        password_hash=owner['password_hash'], is_active=True))
    db.session.add(SystemSettings(id=1, value=json.dumps(settings), revision=1))
    db.session.commit()
