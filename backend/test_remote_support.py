import tempfile
import unittest
from pathlib import Path
from app import create_app
from models import db, User, Sale
from werkzeug.security import generate_password_hash

class RemoteSupportTestCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.app = create_app({'TESTING':True, 'SQLALCHEMY_DATABASE_URI':'sqlite:///' + (self.root/'test.db').as_posix(), 'LICENSE_DATA_DIR':str(self.root)})
        self.client = self.app.test_client()
        with self.app.app_context():
            for role in ['owner','cashier']:
                db.session.add(User(username=role,full_name=role,role=role,password_hash=generate_password_hash('password123')))
            db.session.commit()
        self.headers = {}
        for role in ['owner','cashier']:
            login = self.client.post('/api/auth/login',json={'username':role,'password':'password123'})
            self.headers[role] = {'Authorization':'Bearer '+login.json['token']}
    def tearDown(self):
        with self.app.app_context(): db.session.remove(); db.engine.dispose()
        self.temp.cleanup()
    def test_no_fake_remote_connection_and_permission_boundary(self):
        status = self.client.get('/api/support/status',headers=self.headers['owner'])
        self.assertFalse(status.json['is_active'])
        self.assertFalse(status.json['available'])
        self.assertEqual(self.client.post('/api/support/request',headers=self.headers['owner'],json={'level':3}).status_code,503)
        self.assertEqual(self.client.post('/api/support/repair-db',headers=self.headers['cashier'],json={'consent':True}).status_code,403)
        self.assertEqual(self.client.get('/api/support/status').status_code,401)
    def test_local_backup_requires_consent_and_does_not_edit_sales(self):
        self.assertEqual(self.client.post('/api/support/repair-db',headers=self.headers['owner']).status_code,400)
        with self.app.app_context(): before = Sale.query.count()
        result = self.client.post('/api/support/repair-db',headers=self.headers['owner'],json={'consent':True})
        self.assertEqual(result.status_code,200,result.json)
        self.assertEqual(result.json['results']['integrity'],'ok')
        self.assertTrue((self.root/'backups'/result.json['results']['backup']).is_file())
        with self.app.app_context(): self.assertEqual(before,Sale.query.count())
        self.assertEqual(len(self.client.get('/api/support/status',headers=self.headers['owner']).json['logs']),1)

if __name__ == '__main__': unittest.main()
