import unittest
from test_workflows import WorkflowTests
from models import db, User
from role_access import permissions_for, role_descriptors


class SettingsTests(unittest.TestCase):
    setUp = WorkflowTests.setUp
    tearDown = WorkflowTests.tearDown

    def test_settings_permissions_validation_and_conflicts(self):
        before = self.client.get('/api/settings', headers=self.tokens['cash']).json
        changed = before['settings']; changed['tabs']['tables'] = False
        body = dict(settings=changed, revision=before['revision'])
        self.assertEqual(self.client.put('/api/settings',headers=self.tokens['cash'],json=body).status_code,403)
        self.assertEqual(self.client.put('/api/settings',headers=self.tokens['owner'],json=body).status_code,200)
        self.assertEqual(self.client.put('/api/settings',headers=self.tokens['owner'],json=body).status_code,409)
        self.assertFalse(self.client.get('/api/settings',headers=self.tokens['cash']).json['settings']['tabs']['tables'])
        body['settings']['session_hours'] = 0
        self.assertEqual(self.client.put('/api/settings',headers=self.tokens['owner'],json=body).status_code,400)

    def test_open_table_cannot_be_hidden(self):
        body = WorkflowTests.cart(self)
        self.assertEqual(self.client.post('/api/tables/1/order',headers=self.tokens['cash'],json=body).status_code,200)
        settings = self.client.get('/api/settings',headers=self.tokens['owner']).json
        settings['settings']['tabs']['tables'] = False
        self.assertEqual(self.client.put('/api/settings',headers=self.tokens['owner'],json=settings).status_code,409)

    def test_builtin_edit_and_revoke_without_lockout(self):
        self.assertEqual(self.client.put('/api/roles/cashier',headers=self.tokens['owner'],
            json={'name':'بائع','permissions':['sales.create']}).status_code,200)
        self.assertEqual(permissions_for('cashier'), {'sales.create','products.view'})
        self.assertEqual(self.client.get('/api/products',headers=self.tokens['cash']).status_code,401)
        self.assertEqual(sum(r['id']=='cashier' for r in role_descriptors()),1)
        self.assertEqual(self.client.put('/api/roles/developer',headers=self.tokens['owner'],json={'name':'مطور','permissions':[]}).status_code,403)
        self.assertEqual(self.client.delete('/api/roles/cashier',headers=self.tokens['owner']).status_code,400)
        self.assertEqual(self.client.put('/api/roles/owner',headers=self.tokens['owner'],json={'name':'مالك','permissions':[]}).status_code,200)
        self.assertIn('roles.manage',permissions_for('owner'))
        self.assertIn('settings.manage',permissions_for('owner'))


if __name__ == '__main__': unittest.main()
