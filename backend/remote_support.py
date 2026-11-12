"""Local diagnostics only. Remote transport stays unavailable until configured."""
import json
import sqlite3
import uuid
from collections import deque
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from flask import Blueprint, request, jsonify, g, current_app
from models import db
from security import failure

support_bp = Blueprint('remote_support', __name__)


def audit_path():
    folder = Path(current_app.config.get('LICENSE_DATA_DIR') or Path(__file__).resolve().parent / 'logs')
    folder.mkdir(parents=True, exist_ok=True)
    return folder / 'support_audit.jsonl'


def log_audit(action, details):
    entry = dict(timestamp=datetime.now(timezone.utc).isoformat(), action=action, details=details,
                 user=g.current_user.username, ip=request.remote_addr, level=1)
    with audit_path().open('a', encoding='utf-8') as file:
        file.write(json.dumps(entry, ensure_ascii=False) + '\n')


@support_bp.get('/api/support/status')
def support_status():
    logs = []
    path = audit_path()
    if path.is_file():
        with path.open(encoding='utf-8') as file:
            for line in reversed(deque(file, maxlen=30)):
                try: logs.append(json.loads(line))
                except ValueError: pass
    return jsonify(status='success', is_active=False, available=False, code=None, logs=logs,
                   message='الدعم عن بُعد غير موصول حالياً. الفحص المحلي متاح ولا يرسل بيانات خارج الجهاز.')


@support_bp.post('/api/support/request')
def request_support():
    return failure('الدعم عن بُعد لم يُربط بخادم الدعم بعد. لا توجد جلسة اتصال نشطة.', 503)


@support_bp.post('/api/support/terminate')
def terminate_support():
    return jsonify(status='success', message='لا يوجد اتصال دعم عن بُعد نشط.')


@support_bp.post('/api/support/repair-db')
def repair_database():
    data = request.get_json(silent=True) or {}
    if data.get('consent') is not True:
        return failure('أكد موافقتك على الفحص المحلي والنسخة الاحتياطية.', 400)
    if db.engine.dialect.name != 'sqlite':
        return failure('الفحص المحلي متاح لقواعد SQLite.', 400)
    source = db.engine.url.database
    if not source or source == ':memory:': return failure('لا يوجد ملف قاعدة بيانات محلي للفحص.', 400)
    folder = Path(current_app.config.get('LICENSE_DATA_DIR') or Path(source).parent) / 'backups'
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / ('diagnostic-' + datetime.now().strftime('%Y%m%d-%H%M%S-') + uuid.uuid4().hex[:8] + '.db')
    try:
        # SQLite backup handles active WAL files and open readers consistently.
        with closing(sqlite3.connect(Path(source).resolve().as_uri() + '?mode=ro', uri=True, timeout=10)) as connection:
            with closing(sqlite3.connect(target)) as backup:
                connection.backup(backup)
                integrity = [r[0] for r in backup.execute('PRAGMA integrity_check')]
                foreign = list(backup.execute('PRAGMA foreign_key_check'))
        log_audit('LOCAL_DIAGNOSTICS', 'أُنشئت نسخة احتياطية وفُحصت سلامة البيانات بدون تعديل الفواتير.')
        return jsonify(status='success', results=dict(backup=target.name, integrity='ok' if integrity == ['ok'] else integrity,
            foreign_key_issues=len(foreign), fixes=[], message='الفحص لا يعدل المبيعات أو يحذفها.'))
    except (OSError, sqlite3.Error):
        return failure('تعذر إكمال النسخة الاحتياطية أو الفحص. لم تُعدّل البيانات.', 500)
