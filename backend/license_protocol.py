"""Versioned offline license protocol. This module contains no signing keys."""
import base64
import hashlib
import json
import re
from datetime import datetime, timezone
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

PSS = padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=32)
LIMIT = 65536


class LicenseError(ValueError):
    pass


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')


def encode(raw):
    return base64.urlsafe_b64encode(raw).decode('ascii').rstrip('=')


def decode(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', value) or len(value) > LIMIT:
        raise LicenseError('رمز غير صالح.')
    try:
        return base64.b64decode(value + '=' * (-len(value) % 4), altchars=b'-_', validate=True)
    except ValueError as error:
        raise LicenseError('رمز غير صالح.') from error


def public_pem(key):
    return key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)


def sign(payload, private_key):
    raw = canonical(payload)
    return encode(raw) + '.' + encode(private_key.sign(raw, PSS, hashes.SHA256()))


def verify(token, public_key_pem, kind):
    if not isinstance(token, str) or len(token) > LIMIT:
        raise LicenseError('حجم الرمز غير صالح.')
    try:
        body, signature = token.strip().split('.')
        raw = decode(body)
        key = serialization.load_pem_public_key(public_key_pem)
        if not isinstance(key, rsa.RSAPublicKey) or key.key_size < 3072:
            raise LicenseError('مفتاح الترخيص غير صالح.')
        key.verify(decode(signature), raw, PSS, hashes.SHA256())
        payload = json.loads(raw)
        if not isinstance(payload, dict) or payload.get('kind') != kind or payload.get('version') != 1:
            raise LicenseError('نوع الرمز أو إصداره غير صالح.')
        return payload
    except (InvalidSignature, ValueError, TypeError, UnicodeError) as error:
        raise LicenseError('التوقيع غير صحيح أو الرمز تالف.') from error


def make_request(edition_id, fingerprint):
    return 'POSREQ1-' + encode(canonical(dict(version=1, edition_id=edition_id, fingerprint=fingerprint)))


def parse_request(code):
    try:
        if not code.strip().startswith('POSREQ1-'):
            raise ValueError()
        value = json.loads(decode(code.strip()[8:]))
        if value.get('version') != 1 or not re.fullmatch(r'[a-f0-9]{32}', value['edition_id']) or not re.fullmatch(r'[a-f0-9]{64}', value['fingerprint']):
            raise ValueError()
        return value
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise LicenseError('كود طلب التفعيل غير صالح.') from error


def check_binding(payload, edition_id, fingerprint, now=None):
    if payload.get('edition_id') != edition_id or payload.get('fingerprint') != fingerprint:
        raise LicenseError('هذا الترخيص يخص جهازاً أو نسخة أخرى.')
    now = now or datetime.now(timezone.utc)
    try:
        issued = datetime.fromisoformat(payload['issued_at'])
        expiry = datetime.fromisoformat(payload['expires_at']) if payload.get('expires_at') else None
        if issued.tzinfo is None or (expiry and expiry.tzinfo is None):
            raise ValueError()
        if now < issued:
            raise LicenseError('تاريخ الجهاز أقدم من تاريخ إصدار الترخيص. صحح ساعة الجهاز.')
        if expiry and now >= expiry:
            raise LicenseError('انتهت مدة الترخيص. اطلب تجديده من الإدارة.')
    except (KeyError, TypeError, ValueError) as error:
        if isinstance(error, LicenseError):
            raise
        raise LicenseError('تواريخ الترخيص غير صالحة.') from error


def fingerprint_digest(identifiers):
    return hashlib.sha256(b'pos-hardware-v1\0' + canonical(identifiers)).hexdigest()
