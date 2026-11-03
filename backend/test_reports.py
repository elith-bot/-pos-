import io
import unittest
from datetime import datetime, timedelta
from test_workflows import WorkflowTests
from models import db, Sale, Product
from report_filters import report_window
from report_exports import encode_document, section


class ReportTests(unittest.TestCase):
    setUp = WorkflowTests.setUp
    tearDown = WorkflowTests.tearDown
    cart = WorkflowTests.cart

    def sell(self):
        body = self.cart()
        body['checkout_key'] = 'export-sale'
        response = self.client.post('/api/sales', headers=self.tokens['cash'], json=body)
        self.assertEqual(response.status_code, 201, response.json)
        sale = Sale.query.one()
        sale.created_at = datetime(2026, 11, 3, 7, 30)
        db.session.commit()
        return sale

    def test_custom_time_boundaries_and_invalid_requests(self):
        self.sell()
        params = dict(period='custom_time', start_at='2026-11-03T10:30:00+03:00', end_at='2026-11-03T11:00:00+03:00',tz_offset=180)
        data = self.client.get('/api/stats', query_string=params, headers=self.tokens['owner']).json
        self.assertEqual(data['stats']['total_sales_count'], 1)
        self.assertEqual(data['timeline'][0]['label'], '2026-11-03 10:00')
        exported = self.client.get('/api/reports/export',query_string={**data['resolved_filter'],'format':'json'},headers=self.tokens['owner']).json
        self.assertIn(['صافي المبيعات',4000],exported['sections'][0]['rows'])
        params.update(start_at='2026-11-03T10:00:00+03:00',end_at='2026-11-03T10:30:00+03:00')
        self.assertEqual(self.client.get('/api/stats',query_string=params,headers=self.tokens['owner']).json['stats']['total_sales_count'],0)
        params['start_at'] = 'invalid'
        self.assertEqual(self.client.get('/api/stats',query_string=params,headers=self.tokens['owner']).status_code,400)
        for hours in ['0','-1','nan','inf','8761']:
            self.assertEqual(self.client.get('/api/stats',query_string={'period':'hours','hours':hours},headers=self.tokens['owner']).status_code,400)

    def test_hour_presets_and_frozen_export_bounds(self):
        now = datetime(2026,11,3,12)
        for hours in [1,4,6,8,12,16,3.5]:
            result = report_window({'period':'hours','hours':str(hours),'tz_offset':'180'}, now)
            self.assertEqual(result[3],now-timedelta(hours=hours))
            self.assertEqual(result[4],now)
            again = report_window(result[-1],now+timedelta(days=1))
            self.assertEqual(again[3:5],result[3:5])

    def test_formats_and_cashier_redaction(self):
        sale = self.sell()
        from openpyxl import load_workbook
        for fmt in ['pdf','xlsx','csv','json']:
            r = self.client.get('/api/reports/export',query_string={'period':'all','format':fmt},headers=self.tokens['owner'])
            self.assertEqual(r.status_code,200,r.data[:200])
            self.assertIn('attachment',r.headers['Content-Disposition'])
            if fmt == 'pdf': self.assertTrue(r.data.startswith(b'%PDF'))
            if fmt == 'xlsx':
                wb = load_workbook(io.BytesIO(r.data),data_only=False)
                self.assertIn('تفاصيل المنتجات', wb.sheetnames)
                self.assertTrue(wb['الملخص'].sheet_view.rightToLeft)
            self.assertEqual(self.client.get('/api/reports/export',query_string={'format':fmt},headers=self.tokens['cash']).status_code,403)
        own = self.client.get(f'/api/sales/{sale.id}/export?format=json',headers=self.tokens['cash']).json
        self.assertNotIn('الكلفة',own['sections'][0]['columns'])
        self.assertNotIn('الربح',own['sections'][1]['columns'])
        sale.cashier_id = 1
        db.session.commit()
        self.assertEqual(self.client.get(f'/api/sales/{sale.id}/export?format=json',headers=self.tokens['cash']).status_code,403)

    def test_draft_export_no_side_effects_and_spreadsheet_text(self):
        before=db.session.get(Product,self.product).stock_quantity
        r=self.client.post('/api/cart/export?format=json',headers=self.tokens['cash'],json=self.cart())
        self.assertEqual(r.status_code,200,r.json)
        self.assertEqual(r.json['sections'][0]['rows'][0][-1],4000)
        self.assertEqual(Sale.query.count(),0)
        self.assertEqual(db.session.get(Product,self.product).stock_quantity,before)
        from openpyxl import load_workbook
        doc=dict(title='تجربة عربية',notes=[],sections=[section('اختبار',['المنتج','القيمة'],[['=1+1',12],['شوكولاتة جالاكسي',20]])])
        raw,_=encode_document(doc,'xlsx')
        wb=load_workbook(io.BytesIO(raw));self.assertEqual(wb.active['A3'].data_type,'s')
        raw,_=encode_document(doc,'csv');self.assertIn("'=1+1",raw.decode('utf-8-sig'))


if __name__ == '__main__': unittest.main()
