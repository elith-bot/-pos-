"""Offline vendor operations. Never include this directory in customer installers."""
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from werkzeug.security import generate_password_hash
from license_protocol import sign, verify, public_pem, parse_request, LicenseError
from system_settings import validate_settings
from role_access import normalize_permissions, BUILTINS


def create_key(path, password):
    path = Path(path)
    if len(password) < 12:
        raise ValueError('اختر كلمة حماية للمفتاح من 12 حرفاً على الأقل واحفظ نسخة احتياطية منها.')
    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as file:
        file.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                     serialization.BestAvailableEncryption(password.encode('utf-8'))))
    return key


def unlock_key(path, password):
    key = serialization.load_pem_private_key(Path(path).read_bytes(), password=password.encode('utf-8'))
    if not isinstance(key, rsa.RSAPrivateKey) or key.key_size < 3072:
        raise ValueError('مفتاح الإدارة غير صالح.')
    return key


def create_edition(output_root, key, customer, owner, settings, roles, vendor_name=""):
    for field in ['name', 'phone', 'address', 'notes']:
        if not isinstance(customer.get(field), str) or len(customer[field]) > 2000:
            raise ValueError('بيانات الزبون غير صالحة.')
    if not customer['name'].strip():
        raise ValueError('اسم الزبون مطلوب.')
    if not re.fullmatch(r'\+?[0-9]{7,20}', owner.get('phone', '')) or len(owner.get('password', '')) < 8:
        raise ValueError('رقم المالك مطلوب، وكلمة المرور 8 أحرف على الأقل.')
    owner_name = owner.get('name', customer['name']).strip()
    if not owner_name or len(owner_name) > 120: raise ValueError('اسم المالك مطلوب وبحد أقصى 120 حرفاً.')
    if not isinstance(vendor_name, str) or len(vendor_name) > 120: raise ValueError('اسم الشركة أطول من الحد المسموح.')
    validated_roles = []
    seen_ids, seen_names = set(), set()
    for role in roles:
        role_id, name = role['id'], role['name'].strip()
        if (role_id not in BUILTINS and not re.fullmatch(r'role_[a-f0-9]{12}', role_id)) or role_id in seen_ids or name in seen_names or not 1 <= len(name) <= 80:
            raise ValueError('اسم أو معرّف دور مكرر أو غير صالح.')
        seen_ids.add(role_id); seen_names.add(name)
        validated_roles.append(dict(id=role_id, name=name, permissions=sorted(normalize_permissions(role['permissions']))))
    payload = dict(kind='deployment', version=1, edition_id=uuid.uuid4().hex,
                   issued_at=datetime.now(timezone.utc).isoformat(), customer=customer,
                   vendor_name=vendor_name.strip(), owner=dict(name=owner_name, phone=owner['phone'], password_hash=generate_password_hash(owner['password'])),
                   settings=validate_settings(settings), roles=validated_roles)
    folder = Path(output_root) / payload['edition_id']
    folder.mkdir(parents=True, exist_ok=False)
    (folder / 'deployment.pos').write_text(sign(payload, key), encoding='utf-8')
    (folder / 'license-public.pem').write_bytes(public_pem(key))
    return folder


def issue_license(edition_folder, request_code, key, expires_at=None):
    edition_folder = Path(edition_folder)
    deployment = verify((edition_folder / 'deployment.pos').read_text(encoding='utf-8'), public_pem(key), 'deployment')
    request = parse_request(request_code)
    if request['edition_id'] != deployment['edition_id']:
        raise LicenseError('طلب التفعيل لا يخص نسخة الزبون المختارة.')
    now = datetime.now(timezone.utc)
    if expires_at:
        expiry = datetime.fromisoformat(expires_at)
        if expiry.tzinfo is None or expiry <= now:
            raise LicenseError('تاريخ انتهاء الترخيص يجب أن يكون مستقبلياً مع المنطقة الزمنية.')
    payload = dict(kind='license', version=1, license_id=uuid.uuid4().hex,
                   edition_id=deployment['edition_id'], fingerprint=request['fingerprint'],
                   customer_name=deployment['customer']['name'], issued_at=now.isoformat(), expires_at=expires_at)
    token = sign(payload, key)
    licenses = edition_folder / 'issued-licenses'
    licenses.mkdir(exist_ok=True)
    # New license per issuance; previous licenses and local audit history remain intact.
    (licenses / (payload['license_id'] + '.lic')).write_text(token, encoding='utf-8')
    with (edition_folder / 'issuance-log.jsonl').open('a', encoding='utf-8') as file:
        file.write(json.dumps(payload, ensure_ascii=False) + '\n')
    return token


def find_edition(request_code, key, roots):
    """Resolve an exact, signature-verified edition without guessing a customer."""
    edition_id = parse_request(request_code)['edition_id']
    for root in roots:
        folder = Path(root) / edition_id
        manifest = folder / 'deployment.pos'
        if not manifest.is_file(): continue
        payload = verify(manifest.read_text(encoding='utf-8'), public_pem(key), 'deployment')
        if payload['edition_id'] == edition_id: return folder
    return None
