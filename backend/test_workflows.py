import unittest
from datetime import datetime
from unittest.mock import patch
from werkzeug.security import generate_password_hash
from app import create_app
from models import db, User, Product, Sale, Table, AuthSession

class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app({'TESTING': True, 'SQLALCHEMY_DATABASE_URI': 'sqlite:///:memory:'})
        self.ctx = self.app.app_context()
        self.ctx.push()
        self.client = self.app.test_client()
        for name, role in [('cash', 'cashier'), ('manager', 'admin'), ('owner', 'owner')]:
            db.session.add(User(username=name, full_name=name, role=role, is_active=True,
                password_hash=generate_password_hash('testpass123')))
        product = Product(name='Weighted', purchase_price=6000, selling_price=10000,
            stock_quantity=5000, is_weight=True, weight_unit_grams=1000)
        db.session.add(product)
        db.session.add(Table(table_number=1))
        db.session.commit()
        self.product = product.id
        self.tokens = {}
        for name in ['admin', 'cash', 'manager', 'owner']:
            response = self.client.post('/api/auth/login', json={'username':name,
                'password':'admin123' if name == 'admin' else 'testpass123'})
            self.tokens[name] = {'Authorization':'Bearer ' + response.json['token']}

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.ctx.pop()

    def cart(self):
        return {'items':[{'product_id':self.product,'quantity':500,
            'unit_selling_price':10000,'unit_purchase_price':1,'discount':1000}],
            'global_discount':500}

    def test_permissions_and_private_costs(self):
        self.assertEqual(self.client.get('/api/products').status_code,401)
        for path in ['/api/users','/api/stats','/api/expenses','/api/sales']:
            self.assertEqual(self.client.get(path,headers=self.tokens['cash']).status_code,403)
        products=self.client.get('/api/products',headers=self.tokens['cash']).json['products']
        self.assertNotIn('purchase_price',products[0])
        self.assertEqual(self.client.post('/api/auth/request-otp',json={'username':'admin'}).status_code,401)

    def test_role_hierarchy_and_revocation(self):
        cash=User.query.filter_by(username='cash').first()
        owner=User.query.filter_by(username='owner').first()
        manager=User.query.filter_by(username='manager').first()
        self.assertEqual(self.client.put(f'/api/users/{owner.id}/role',headers=self.tokens['manager'],json={'role':'cashier'}).status_code,403)
        self.assertEqual(self.client.put(f'/api/users/{manager.id}/toggle-active',headers=self.tokens['manager']).status_code,403)
        self.assertEqual(self.client.put(f'/api/users/{cash.id}/toggle-active',headers=self.tokens['manager']).status_code,200)
        self.assertEqual(self.client.get('/api/products',headers=self.tokens['cash']).status_code,401)

    def test_weighted_table_checkout_and_idempotency(self):
        body=self.cart()
        self.assertEqual(self.client.post('/api/tables/1/order',headers=self.tokens['cash'],json=body).status_code,200)
        order=self.client.get('/api/tables/1/order',headers=self.tokens['cash']).json['order']
        self.assertEqual(order['total_amount'],4000)
        self.assertEqual(order['cart_state']['global_discount'],500)
        self.assertEqual(self.client.get('/api/tables',headers=self.tokens['cash']).json['tables'][0]['total_price'],4000)
        body.update(table_id=1,checkout_key='test-one',cashier_name='forged')
        response=self.client.post('/api/sales',headers=self.tokens['cash'],json=body)
        self.assertEqual(response.status_code,201,response.json)
        sale=Sale.query.one()
        self.assertEqual(sale.cashier_name,'cash')
        self.assertEqual(sale.total_purchase_cost,3000)
        self.assertEqual(sale.net_profit,1000)
        self.assertEqual(sale.order_type, 'table')
        self.assertEqual(sale.table_name, 'طاولة 1')
        # Sale metadata remains historical even if the catalogue unit changes.
        db.session.get(Product,self.product).weight_unit_grams = 500
        db.session.commit()
        detail = sale.to_dict()['items'][0]
        self.assertTrue(detail['is_weight'])
        self.assertEqual(detail['weight_unit_grams'], 1000)
        self.assertEqual(detail['gross_amount'], 5000)
        self.assertEqual(detail['discount_amount'], 1000)
        self.assertEqual(detail['total_purchase_cost'], 3000)
        self.assertNotIn('total_purchase_cost', response.json['sale'])
        self.assertNotIn('profit', response.json['sale']['items'][0])
        self.assertNotIn('total_purchase_cost', response.json['sale']['items'][0])
        for role in ['admin', 'manager', 'owner']:
            report = self.client.get('/api/stats?period=all', headers=self.tokens[role])
            self.assertEqual(report.status_code, 200)
            self.assertEqual(report.json['sales'][0]['items'][0]['gross_amount'], 5000)
            self.assertEqual(report.json['sales'][0]['net_profit'], 1000)
        self.assertEqual(sum(i.profit for i in sale.items),1000)
        self.assertEqual(db.session.get(Product,self.product).stock_quantity,4500)
        self.assertEqual(self.client.post('/api/sales',headers=self.tokens['cash'],json=body).status_code,200)
        self.assertEqual(Sale.query.count(),1)
        self.assertFalse(db.session.get(Table,1).is_active)

    def test_bad_amounts_and_stock_rollback(self):
        for qty in [-1,0,6000,float('nan')]:
            body=self.cart()
            body['items'][0]['quantity']=qty
            body['checkout_key']='bad'
            self.assertEqual(self.client.post('/api/sales',headers=self.tokens['cash'],json=body).status_code,400)
            self.assertEqual(Sale.query.count(),0)
            self.assertEqual(db.session.get(Product,self.product).stock_quantity,5000)

    def test_today_report_after_checkout_and_local_day_boundary(self):
        def report(period='today'):
            response = self.client.get('/api/stats', query_string={
                'period': period, 'tz_offset': 180}, headers=self.tokens['manager'])
            self.assertEqual(response.status_code, 200)
            return response.json

        self.assertEqual(report()['stats']['total_sales_count'], 0)
        body = self.cart()
        self.client.post('/api/tables/1/order', headers=self.tokens['cash'], json=body)
        self.assertEqual(report()['stats']['total_sales_count'], 0)
        body.update(table_id=1, checkout_key='report-sale')
        response = self.client.post('/api/sales', headers=self.tokens['cash'], json=body)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(report()['stats']['total_revenue'], 4000)
        self.assertEqual(report()['stats']['total_sales_count'], 1)
        # 21:30 UTC belongs to the following day in Baghdad.
        Sale.query.one().created_at = datetime(2026, 10, 31, 21, 30)
        db.session.commit()
        with patch('report_filters.datetime') as clock:
            clock.utcnow.return_value = datetime(2026, 10, 31, 22)
            clock.side_effect = datetime
            today = report()
            self.assertEqual(today['start_date'], '2026-11-01')
            self.assertEqual(today['stats']['total_sales_count'], 1)
            self.assertEqual(today['timeline'][0]['revenue'], 4000)
            self.assertEqual(report('yesterday')['stats']['total_sales_count'], 0)

    def test_employee_creation_logout(self):
        body={'username':'new','password':'testpass123','full_name':'New User'}
        self.assertEqual(self.client.post('/api/auth/register',json=body).status_code,401)
        self.assertEqual(self.client.post('/api/auth/register',headers=self.tokens['manager'],json=body).status_code,201)
        self.assertEqual(self.client.post('/api/auth/logout',headers=self.tokens['manager']).status_code,200)
        self.assertEqual(self.client.get('/api/users',headers=self.tokens['manager']).status_code,401)

if __name__ == '__main__':
    unittest.main()

