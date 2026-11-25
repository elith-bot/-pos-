import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric import rsa
from werkzeug.security import check_password_hash

sys.path.append(str(Path(__file__).resolve().parents[1] / 'admin_console'))
from service import create_edition, issue_license, create_key, unlock_key
from license_protocol import make_request, verify, sign, public_pem, LicenseError
from licensing import LicenseManager
from system_settings import preset
from app import create_app
from models import db, User, Product


class OfflineLicenseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=3072)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.edition = create_edition(self.root, self.key,
            dict(name='اختبار', phone='07700000000', address='بغداد', notes='test'),
            dict(phone='07700000000', password='private-test-password'), preset('supermarket'), [])
        self.manager = LicenseManager(self.edition, self.root / 'data', fingerprint=lambda: 'a'*64)
        self.request = make_request(self.edition.name, 'a'*64)
        self.token = issue_license(self.edition, self.request, self.key)

    def tearDown(self):
        self.temp.cleanup()

    def test_customer_contact_is_separate_from_business_and_owner(self):
        folder = create_edition(self.root, self.key,
            dict(name='متجر القمر', customer_name='مسؤول الزبون', phone='07700000000', address='بغداد', notes=''),
            dict(name='صاحب المتجر', phone='07800000000', password='private-test-password'),
            preset('supermarket'), [], vendor_name='moon')
        deployment = verify((folder / 'deployment.pos').read_text(encoding='utf-8'), public_pem(self.key), 'deployment')
        self.assertEqual(deployment['customer']['customer_name'], 'مسؤول الزبون')
        self.assertEqual(deployment['customer']['name'], 'متجر القمر')
        self.assertEqual(deployment['owner']['name'], 'صاحب المتجر')

    def test_offline_activation_restart_and_no_plain_password(self):
        self.assertFalse(self.manager.status()['active'])
        self.manager.activate(self.token)
        restarted = LicenseManager(self.edition, self.root / 'data', fingerprint=lambda: 'a'*64)
        self.assertTrue(restarted.status()['active'])
        self.assertNotIn('private-test-password', json.dumps(self.manager.deployment))
        self.assertTrue(check_password_hash(self.manager.deployment['owner']['password_hash'], 'private-test-password'))

    def test_copy_tamper_wrong_key_and_wrong_edition(self):
        self.manager.activate(self.token)
        copied = LicenseManager(self.edition, self.root / 'data', fingerprint=lambda: 'b'*64)
        self.assertFalse(copied.status()['active'])
        self.assertTrue(self.manager.path.exists())
        payload = verify(self.token, public_pem(self.key), 'license')
        for value in [self.token.replace('.', 'a.', 1), sign({**payload, 'edition_id':'b'*32}, self.key),
                      sign(payload, rsa.generate_private_key(public_exponent=65537, key_size=3072)),
                      (self.edition / 'deployment.pos').read_text(), None, '', 'x'*70000]:
            with self.assertRaises(LicenseError): self.manager.activate(value)
            self.assertEqual(self.manager.path.read_text(), self.token)

    def test_expiry_and_mismatched_request(self):
        payload = verify(self.token, public_pem(self.key), 'license')
        expired = sign({**payload, 'expires_at':(datetime.now(timezone.utc)-timedelta(days=1)).isoformat()}, self.key)
        with self.assertRaises(LicenseError): self.manager.activate(expired)
        future = sign({**payload, 'issued_at':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()}, self.key)
        with self.assertRaises(LicenseError): self.manager.activate(future)
        with self.assertRaises(LicenseError): issue_license(self.edition, make_request('b'*32, 'a'*64), self.key)

    def test_backend_gate_bootstrap_and_activation(self):
        app = create_app(dict(TESTING=True, LICENSE_REQUIRED=True, LICENSE_BUNDLE_DIR=str(self.edition),
            LICENSE_DATA_DIR=str(self.root / 'data'), HARDWARE_FINGERPRINT=lambda:'a'*64,
            SQLALCHEMY_DATABASE_URI='sqlite:///:memory:'))
        client = app.test_client()
        with app.app_context():
            self.assertEqual(User.query.count(),1)
            self.assertEqual(User.query.first().role,'owner')
            self.assertEqual(Product.query.count(),0)
        self.assertEqual(client.post('/api/auth/login', json={}).status_code,423)
        self.assertEqual(client.get('/api/products').status_code,423)
        self.assertFalse(client.get('/api/license').json['active'])
        self.assertEqual(client.post('/api/license/activate', json={'token':self.token}, headers={'Origin':'https://foreign.example'}).status_code,403)
        self.assertEqual(client.post('/api/license/activate', json={'token':self.token}, environ_base={'REMOTE_ADDR':'192.168.1.5'}).status_code,403)
        self.assertEqual(client.post('/api/license/activate', json={'token':self.token}).status_code,200)
        login = client.post('/api/auth/login', json={'username':'07700000000','password':'private-test-password'})
        self.assertEqual(login.status_code,200)
        headers = {'Authorization':'Bearer '+login.json['token']}
        self.assertEqual(client.get('/api/products',headers=headers).status_code,200)
        self.assertFalse(client.get('/api/settings',headers=headers).json['settings']['tabs']['tables'])
        self.manager.path.write_text('tampered')
        self.assertEqual(client.get('/api/products',headers=headers).status_code,423)

    def test_missing_release_manifest_fails_closed(self):
        app = create_app(dict(TESTING=True, LICENSE_REQUIRED=True, LICENSE_BUNDLE_DIR=str(self.root/'missing'),
            LICENSE_DATA_DIR=str(self.root/'empty'), SQLALCHEMY_DATABASE_URI='sqlite:///:memory:'))
        with app.app_context(): self.assertEqual(User.query.count(),0)
        self.assertEqual(app.test_client().post('/api/auth/login', json={}).status_code,423)

    def test_encrypted_private_key_cannot_be_overwritten(self):
        path = self.root / 'private.pem'
        key = create_key(path, 'long-password-for-key')
        self.assertIn(b'ENCRYPTED PRIVATE KEY', path.read_bytes())
        self.assertEqual(public_pem(unlock_key(path, 'long-password-for-key')), public_pem(key))
        with self.assertRaises(ValueError): unlock_key(path, 'incorrect-password')
        with self.assertRaises(FileExistsError): create_key(path, 'long-password-for-key')


if __name__ == '__main__': unittest.main()
