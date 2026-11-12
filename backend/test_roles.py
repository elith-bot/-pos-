import io, unittest
from test_workflows import WorkflowTests
from models import db, User
from openpyxl import load_workbook
class RoleTests(unittest.TestCase):
 setUp=WorkflowTests.setUp
 tearDown=WorkflowTests.tearDown
 def create(self,permissions):
  r=self.client.post('/api/roles',headers=self.tokens['owner'],json={'name':'تقارير فقط','permissions':permissions})
  self.assertEqual(r.status_code,201,r.json)
  return r.json['role']['id']
 def assign(self,role):
  user=User.query.filter_by(username='cash').one()
  r=self.client.put(f'/api/users/{user.id}/role',headers=self.tokens['owner'],json={'role':role})
  self.assertEqual(r.status_code,200,r.json)
  r=self.client.post('/api/auth/login',json={'username':'cash','password':'testpass123'})
  return {'Authorization':'Bearer '+r.json['token']}
 def test_role_permissions_and_revocation(self):
  role=self.create(['exports.reports'])
  token=self.assign(role)
  self.assertEqual(self.client.get('/api/stats?period=all',headers=token).status_code,200)
  self.assertEqual(self.client.post('/api/sales',headers=token,json={}).status_code,403)
  stats=self.client.get('/api/stats?period=all',headers=token).json['stats']
  self.assertNotIn('total_cost',stats);self.assertNotIn('profit',stats)
  doc=self.client.get('/api/reports/export?period=all&format=json',headers=token).json
  self.assertNotIn('الكلفة',doc['sections'][1]['columns'])
  self.assertEqual(self.client.delete('/api/roles/'+role,headers=self.tokens['owner']).status_code,409)
  self.assertEqual(self.client.put('/api/roles/'+role,headers=self.tokens['owner'],json={'name':'تقارير','permissions':[]}).status_code,200)
  self.assertEqual(self.client.get('/api/stats',headers=token).status_code,401)
 def test_protected_capabilities(self):
  for headers,permissions in [(self.tokens['cash'],[]),(self.tokens['owner'],['system.core']),(self.tokens['owner'],['roles.manage'])]:
   self.assertIn(self.client.post('/api/roles',headers=headers,json={'name':'مرفوض','permissions':permissions}).status_code,[400,403])
 def test_detailed_workbook(self):
  body=WorkflowTests.cart(self);body['checkout_key']='details'
  self.assertEqual(self.client.post('/api/sales',headers=self.tokens['cash'],json=body).status_code,201)
  r=self.client.get('/api/reports/export?period=all&format=xlsx',headers=self.tokens['owner'])
  self.assertEqual(r.status_code,200)
  wb=load_workbook(io.BytesIO(r.data))
  self.assertIn('تفاصيل كل طلب',wb.sheetnames)
  self.assertTrue(all(ws.sheet_view.rightToLeft for ws in wb))
  self.assertTrue(any(c.hyperlink for row in wb['الطلبات'] for c in row))
  self.assertTrue(any(c.value=='Weighted' for row in wb['تفاصيل كل طلب'] for c in row))
if __name__=='__main__':unittest.main()
