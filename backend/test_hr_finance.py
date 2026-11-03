import unittest
from test_workflows import WorkflowTests
from models import db, User, Product, Expense
from hr_models import Staff


class HRFinanceTests(unittest.TestCase):
    setUp = WorkflowTests.setUp
    tearDown = WorkflowTests.tearDown
    cart = WorkflowTests.cart

    def staff(self, **terms):
        cash = User.query.filter_by(username='cash').one()
        response = self.client.post('/api/hr/staff', headers=self.tokens['owner'], json={
            'name': 'Employee', 'start_date': '2026-01-01', 'user_id': cash.id,
            'notes': 'private management note',
            'contract': {'pay_type': 'monthly', 'rate': 1000, 'effective_month': '2026-01',
                'workdays': '0,1,2,3,4,5,6', 'contract_notes': 'My agreed terms', **terms}})
        self.assertEqual(response.status_code, 201, response.json)
        return response.json['staff']['id']

    def attendance(self, staff_id, **fields):
        return self.client.post('/api/hr/attendance', headers=self.tokens['owner'], json={
            'staff_id': staff_id, 'day': '2026-10-01', 'status': 'present',
            'check_in': '09:00', 'check_out': '17:00', **fields})

    def prepare(self, staff_id, **fields):
        return self.client.post('/api/hr/payroll', headers=self.tokens['owner'], json={
            'staff_id': staff_id, 'month': '2026-10', **fields})

    def test_contract_privacy_and_validation(self):
        staff_id = self.staff()
        for actor in ['cash', 'manager']:
            for url in ['/api/hr/staff', '/api/hr/attendance?month=2026-10', '/api/hr/payroll?month=2026-10', '/api/fixed-expenses?month=2026-10']:
                self.assertEqual(self.client.get(url, headers=self.tokens[actor]).status_code, 403)
            self.assertEqual(self.client.put(f'/api/hr/staff/{staff_id}', headers=self.tokens[actor], json={'name': 'forged'}).status_code, 403)
        mine = self.client.get('/api/hr/my-contract?staff_id=999', headers=self.tokens['cash'])
        self.assertEqual(mine.json['contracts'][0]['contract_notes'], 'My agreed terms')
        self.assertNotIn('notes', mine.json['staff'])
        self.assertIsNone(self.client.get('/api/hr/my-contract', headers=self.tokens['manager']).json['staff'])
        self.assertEqual(self.client.get('/api/hr/my-contract').status_code, 401)
        bad = self.client.post('/api/hr/staff', headers=self.tokens['owner'], json={
            'name': 'Bad', 'start_date': '2026-01-01', 'contract': {'rate': -1}})
        self.assertEqual(bad.status_code, 400)
        self.assertEqual(Staff.query.count(), 1)

    def test_contract_payroll_and_idempotent_expense(self):
        sid = self.staff(grace_minutes=5, late_per_minute=2, absence_per_day=100,
                         bonus_type='per_present_day', bonus_amount=10)
        self.assertEqual(self.attendance(sid, check_in='09:15').status_code, 200)
        self.assertEqual(self.attendance(sid, day='2026-10-02', status='absent', check_in='', check_out='').status_code, 200)
        draft = self.prepare(sid, bonus=25, deduction=5, notes='manual adjustment')
        self.assertEqual(draft.status_code, 200, draft.json)
        p = draft.json['payroll']
        self.assertEqual(p['base_salary'], 1000)
        self.assertEqual(p['bonus'], 35)
        self.assertEqual(p['deduction'], 125)
        self.assertEqual(p['net_salary'], 910)
        self.assertEqual(Expense.query.filter_by(source='payroll').count(), 0)
        for _ in range(2):
            paid = self.client.post(f"/api/hr/payroll/{p['id']}/pay", headers=self.tokens['owner'])
            self.assertEqual(paid.status_code, 200, paid.json)
        expense = Expense.query.filter_by(source='payroll').one()
        self.assertEqual(expense.amount, 910)
        self.assertEqual(self.prepare(sid).status_code, 409)
        self.assertEqual(self.attendance(sid).status_code, 400)
        self.assertEqual(self.client.put(f'/api/hr/staff/{sid}', headers=self.tokens['owner'], json={'contract': {'rate': 2000, 'effective_month': '2026-10'}}).status_code, 400)
        self.assertEqual(self.client.put(f'/api/hr/staff/{sid}', headers=self.tokens['owner'], json={'contract': {'rate': 2000, 'effective_month': '2026-11'}}).status_code, 200)
        self.assertEqual(self.client.delete(f'/api/expenses/{expense.id}', headers=self.tokens['owner']).status_code, 409)
        stats = self.client.get('/api/stats?period=all', headers=self.tokens['owner']).json['stats']
        self.assertEqual(stats['salary_expenses'], 910)
        self.assertEqual(stats['loss'], 910)

    def test_hourly_daily_and_stale_draft(self):
        sid = self.staff(pay_type='hourly', rate=20)
        self.assertEqual(self.attendance(sid).status_code, 200)
        draft = self.prepare(sid).json['payroll']
        self.assertEqual(draft['base_salary'], 160)
        self.attendance(sid, check_out='18:00')
        self.assertEqual(self.client.post(f"/api/hr/payroll/{draft['id']}/pay", headers=self.tokens['owner']).status_code, 409)
        self.assertEqual(self.prepare(sid).json['payroll']['base_salary'], 180)
        self.assertEqual(self.attendance(sid, check_out='08:00').status_code, 400)
        self.client.put(f'/api/hr/staff/{sid}', headers=self.tokens['owner'], json={'contract': {'pay_type': 'daily', 'rate': 50, 'effective_month': '2026-11'}})
        self.attendance(sid, day='2026-11-02')
        self.attendance(sid, day='2026-11-03')
        self.assertEqual(self.prepare(sid, month='2026-11').json['payroll']['base_salary'], 100)
        self.assertEqual(self.prepare(sid, month='2026-11', deduction=200, notes='too much').status_code, 400)

    def test_fixed_expenses_paid_once_and_edited_future_amount(self):
        response = self.client.post('/api/fixed-expenses', headers=self.tokens['owner'], json={
            'title': 'Rent', 'amount': 200, 'category': 'إيجار', 'due_day': 1})
        self.assertEqual(response.status_code, 201, response.json)
        rid = response.json['fixed_expense']['id']
        for _ in range(2):
            self.assertIn(self.client.post(f'/api/fixed-expenses/{rid}/pay', headers=self.tokens['owner'], json={'month': '2026-10'}).status_code, [200, 201])
        self.assertEqual(Expense.query.filter_by(source='fixed').count(), 1)
        self.client.put(f'/api/fixed-expenses/{rid}', headers=self.tokens['owner'], json={'amount': 300})
        self.client.post(f'/api/fixed-expenses/{rid}/pay', headers=self.tokens['owner'], json={'month': '2026-11'})
        self.assertEqual(sorted(e.amount for e in Expense.query.filter_by(source='fixed')), [200, 300])
        stats = self.client.get('/api/stats?period=all', headers=self.tokens['owner']).json['stats']
        self.assertEqual(stats['total_expenses'], 500)
        self.assertEqual(stats['rent_expenses'], 500)

    def test_weighted_supply_does_not_double_deduct_profit_and_zero_stock(self):
        response = self.client.post(f'/api/products/{self.product}/restock', headers=self.tokens['manager'], json={'added_quantity': 500, 'purchase_price': 6000})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(Expense.query.filter_by(source='inventory').one().amount, 3000)
        body = self.cart()
        body['checkout_key'] = 'financial-sale'
        self.assertEqual(self.client.post('/api/sales', headers=self.tokens['cash'], json=body).status_code, 201)
        stats = self.client.get('/api/stats?period=all', headers=self.tokens['owner']).json['stats']
        self.assertEqual(stats['total_cost'], 3000)
        self.assertEqual(stats['gross_profit'], 1000)
        self.assertEqual(stats['final_net_profit'], 1000)
        self.assertEqual(stats['total_supply'], 3000)
        self.assertEqual(stats['total_expenses'], 0)
        db.session.get(Product, self.product).stock_quantity = 0
        db.session.commit()
        body['checkout_key'] = 'empty-stock'
        self.assertEqual(self.client.post('/api/sales', headers=self.tokens['cash'], json=body).status_code, 400)


if __name__ == '__main__': unittest.main()
