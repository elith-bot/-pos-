"""Fail-closed API gate for customer builds; developer source remains unlicensed."""
import os
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlparse
from flask import jsonify, request
from hardware_identity import hardware_fingerprint
from license_protocol import LicenseError, verify, check_binding, make_request


class LicenseManager:
    def __init__(self, bundle, data_dir, fingerprint=hardware_fingerprint):
        self.bundle = Path(bundle)
        self.data_dir = Path(data_dir)
        self.path = self.data_dir / 'license.lic'
        self._fingerprint_reader = fingerprint
        self._fingerprint = None
        self._read_at = 0
        if getattr(sys, 'frozen', False):
            from trusted_license import PUBLIC_KEY
            self.public_key = PUBLIC_KEY
        else:
            self.public_key = (self.bundle / 'license-public.pem').read_bytes()
        self.deployment = verify((self.bundle / 'deployment.pos').read_text(encoding='utf-8'), self.public_key, 'deployment')
        self.edition_id = self.deployment['edition_id']
        if getattr(sys, 'frozen', False):
            from trusted_license import EDITION_ID
            if self.edition_id != EDITION_ID:
                raise LicenseError('ملفات الإعداد لا تخص هذه النسخة.')

    def fingerprint(self):
        if self._fingerprint is None or time.monotonic() - self._read_at > 300:
            self._fingerprint = self._fingerprint_reader()
            self._read_at = time.monotonic()
        return self._fingerprint

    def validate(self, token):
        payload = verify(token, self.public_key, 'license')
        check_binding(payload, self.edition_id, self.fingerprint())
        return payload

    def status(self):
        try:
            if not self.path.exists():
                raise LicenseError('هذه النسخة تحتاج إلى التفعيل لأول مرة.')
            if self.path.stat().st_size > 65536:
                raise LicenseError('ملف الترخيص غير صالح.')
            license_data = self.validate(self.path.read_text(encoding='utf-8'))
            return dict(required=True, active=True, edition_id=self.edition_id,
                        topology=self.deployment.get('topology', {}),
                        expires_at=license_data.get('expires_at'), message='النسخة مفعّلة على هذا الجهاز.')
        except (OSError, ValueError) as error:
            return dict(required=True, active=False, edition_id=self.edition_id, message=str(error))

    def activate(self, token):
        self.validate(token)  # Never overwrite an existing license on failed verification.
        self.data_dir.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.license-', dir=self.data_dir)
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as file:
                file.write(token.strip())
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary, self.path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def install_licensing(app):
    # Frozen releases cannot opt out with an environment variable or missing file.
    required = bool(getattr(sys, 'frozen', False) or app.config.get('LICENSE_REQUIRED'))
    manager = None
    configuration_error = None
    if required:
        try:
            manager = LicenseManager(app.config['LICENSE_BUNDLE_DIR'], app.config['LICENSE_DATA_DIR'],
                                     app.config.get('HARDWARE_FINGERPRINT', hardware_fingerprint))
        except (OSError, ValueError, KeyError) as error:
            configuration_error = 'ملفات النسخة الأصلية ناقصة أو غير صحيحة. أعد التنصيب من النسخة المعتمدة.'
            app.logger.error('License configuration could not be verified: %s', type(error).__name__)
    app.extensions['pos_license'] = manager

    def status():
        if configuration_error:
            return dict(required=True, active=False, message=configuration_error)
        return manager.status() if manager else dict(required=False, active=True, message='نسخة التطوير المحلية')

    @app.before_request
    def license_gate():
        if request.method == 'OPTIONS' or not request.path.startswith('/api/'):
            return None
        # Enforce LAN network topology boundaries
        topology = app.config.get('TOPOLOGY') or (manager.deployment.get('topology') if manager else {})
        mode = topology.get('mode', 'standalone')
        if mode == 'server' and request.remote_addr not in {'127.0.0.1', '::1', 'localhost'}:
            group_id = topology.get('group_id')
            client_group = request.headers.get('X-POS-Group-ID')
            if group_id and client_group != group_id:
                return jsonify(status='error', code='unauthorized_terminal', message='هذا الجهاز غير مصرح له بالاتصال بسيرفر هذا المحل.'), 403

        if request.endpoint in {'license_status', 'activate_license', 'health_check'}:
            return None

        current = status()
        if not current['active']:
            return jsonify(status='error', code='license_required', message=current['message']), 423

    @app.get('/api/license')
    def license_status():
        current = status()
        if manager:
            try:
                current['request_code'] = make_request(manager.edition_id, manager.fingerprint())
            except LicenseError as error:
                current['message'] = str(error)
        return jsonify(current)

    @app.post('/api/license/activate')
    def activate_license():
        # Activation must be performed on the cashier server itself, not across a LAN.
        origin = request.headers.get('Origin')
        if request.remote_addr not in {'127.0.0.1', '::1'} or (origin and urlparse(origin).hostname not in {'localhost', '127.0.0.1', '::1'}):
            return jsonify(message='فعّل النسخة من جهاز الكاشير الرئيسي.'), 403
        if not manager:
            return jsonify(message=configuration_error or 'هذه نسخة تطوير لا تحتاج التفعيل.'), 400
        if request.content_length and request.content_length > 70000:
            return jsonify(message='حجم رمز التفعيل غير صالح.'), 413
        try:
            data = request.get_json(silent=True)
            if not isinstance(data, dict):
                raise LicenseError('أدخل رمز التفعيل.')
            manager.activate(data.get('token'))
            return jsonify(manager.status())
        except (OSError, ValueError) as error:
            return jsonify(message=str(error)), 400
