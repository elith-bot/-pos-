"""Windows DPAPI protects automatic key unlocking for the current Windows account."""
import base64
import ctypes
import os
import secrets
from ctypes import wintypes
from pathlib import Path
from service import create_key, unlock_key


class Blob(ctypes.Structure):
    _fields_ = [('length', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]


def dpapi(raw, decrypt=False):
    if os.name != 'nt':
        raise RuntimeError('فتح المفتاح تلقائياً مدعوم على ويندوز فقط. استخدم مفتاحاً محمياً بكلمة مرور على الأنظمة الأخرى.')
    buffer = ctypes.create_string_buffer(raw)
    source = Blob(len(raw), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    output = Blob()
    function = ctypes.windll.crypt32.CryptUnprotectData if decrypt else ctypes.windll.crypt32.CryptProtectData
    if not function(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)):
        raise ctypes.WinError()
    try: return ctypes.string_at(output.data, output.length)
    finally: ctypes.windll.kernel32.LocalFree(output.data)


def managed_key(folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    key_path, secret_path = folder / 'signing-private.pem', folder / '.key_secret'
    if key_path.exists():
        if not secret_path.exists():
            raise ValueError('المفتاح الموجود يحتاج كلمة مروره الأصلية. لم يتم تغييره.')
        stored = secret_path.read_text(encoding='ascii').strip()
        password = dpapi(base64.b64decode(stored[7:]), decrypt=True).decode('utf-8') if stored.startswith('DPAPI1:') else stored
        key = unlock_key(key_path, password)
        # Upgrade legacy plaintext secret only after successfully opening the existing key.
        if not stored.startswith('DPAPI1:'):
            protected = 'DPAPI1:' + base64.b64encode(dpapi(password.encode('utf-8'))).decode('ascii')
            temporary = secret_path.with_suffix('.tmp')
            temporary.write_text(protected, encoding='ascii'); os.replace(temporary, secret_path)
        return key
    if secret_path.exists():
        raise ValueError('ملف المفتاح مفقود مع وجود بيانات حمايته. استعد النسخة الاحتياطية؛ لن ننشئ مفتاحاً بديلاً تلقائياً.')
    password = secrets.token_urlsafe(48)
    protected = 'DPAPI1:' + base64.b64encode(dpapi(password.encode('utf-8'))).decode('ascii')
    key = create_key(key_path, password)
    with secret_path.open('x', encoding='ascii') as file: file.write(protected)
    return key
