"""Offline report exports. All formats share the same authorized rows and totals."""
import csv
import io
import json
from pathlib import Path
from datetime import datetime
from xml.sax.saxutils import escape
from flask import request, jsonify, g, send_file
from models import db, Sale
from security import POLICY, MANAGERS, failure
from role_access import has_permission
from transactions import normalized_items, number

SUMMARY = {
    'total_sales_count': 'عدد الطلبات', 'gross_sales': 'البيع قبل الخصم', 'total_discount': 'الخصومات',
    'total_revenue': 'صافي المبيعات', 'total_cost': 'كلفة البضاعة المباعة', 'gross_profit': 'الربح قبل المصاريف',
    'total_expenses': 'المصاريف التشغيلية', 'total_supply': 'شراء وتوريد المخزون', 'total_outflows': 'المصاريف والتوريد',
    'final_net_profit': 'الربح أو الخسارة بعد المصاريف', 'salary_expenses': 'الرواتب المدفوعة',
    'rent_expenses': 'الإيجارات المدفوعة', 'subscription_expenses': 'الاشتراكات المدفوعة',
    'fixed_expenses': 'الالتزامات الشهرية المدفوعة', 'profit': 'الربح الموجب', 'loss': 'الخسارة',
}


def section(name, columns, rows): return dict(name=name, columns=columns, rows=rows)


def sale_sections(sales, costs, profits=None):
    profits = costs if profits is None else profits
    columns = ['الطلب', 'التاريخ والوقت', 'الكاشير', 'الدفع', 'نوع الطلب', 'الطاولة', 'عدد الأصناف', 'البيع قبل الخصم', 'الخصم', 'النهائي']
    if costs: columns += ['الكلفة']
    if profits: columns += ['الربح']
    orders, items = [], []
    item_columns = ['الطلب', 'التاريخ والوقت', 'الكاشير', 'المنتج', 'الكمية / غم', 'وحدة التسعير', 'سعر البيع', 'قبل الخصم', 'خصم السطر', 'صافي السطر']
    if costs: item_columns += ['سعر الشراء', 'الكلفة']
    if profits: item_columns += ['الربح']
    for s in sales:
        gross, discount = s.get('total_selling_amount', 0), s.get('total_discount', 0)
        kind = {'direct':'بيع مباشر','table':'طاولة','draft':'مسودة'}.get(s.get('order_type'),'غير مسجل')
        row = [s.get('id', 'مسودة'), s.get('created_at', ''), s.get('cashier_name', ''), s.get('payment_method', ''), kind, s.get('table_name') or '—', len(s.get('items',[])), gross, discount, round(gross-discount, 2)]
        if costs: row += [s.get('total_purchase_cost')]
        if profits: row += [s.get('net_profit')]
        orders.append(row)
        for item in s.get('items', []):
            unit = f"{item.get('weight_unit_grams')} غم" if item.get('is_weight') else 'قطعة' if item.get('is_weight') is False else 'غير مسجلة'
            r = [s.get('id', 'مسودة'), s.get('created_at',''), s.get('cashier_name',''), item.get('product_name'), item.get('quantity'), unit, item.get('unit_selling_price'), item.get('gross_amount'), item.get('discount_amount'), item.get('total_price')]
            if costs: r += [item.get('unit_purchase_price'), item.get('total_purchase_cost')]
            if profits: r += [item.get('profit')]
            items.append(r)
    return [section('الطلبات', columns, orders), section('تفاصيل المنتجات', item_columns, items)]


def order_details(sales, costs, profits):
    details = []
    for sale in sales:
        orders, items = sale_sections([sale], costs, profits)
        details.append(dict(id=sale.get('id','مسودة'), summary=list(map(list,zip(orders['columns'],orders['rows'][0]))),
            items=section('منتجات الطلب',items['columns'][3:], [row[3:] for row in items['rows']])))
    return details


def report_document(data):
    costs, profits = has_permission('financial.costs'), has_permission('financial.profit')
    excluded = set()
    if not costs: excluded.update(['total_cost','total_supply','total_outflows','sales_less_outflows'])
    if not profits: excluded.update(['gross_profit','final_net_profit','profit','loss'])
    sections = [section('الملخص', ['البند', 'القيمة'], [[v, data['stats'].get(k, 0)] for k,v in SUMMARY.items() if k not in excluded]),
        *sale_sections(data['sales'], costs, profits),
        section('المصاريف', ['التاريخ والوقت','العنوان','التصنيف','المبلغ','المسجل','ملاحظات'], [[e['created_at'],e['title'],e['category'],e['amount'],e['created_by'],e.get('notes','')] for e in data.get('expenses', [])]),
        section('الحركة الزمنية', ['الفترة','الإيراد',*(['الربح'] if profits else []),'الطلبات'], [[t['label'],t['revenue'],*([t['profit']] if profits else []),t['orders']] for t in data['timeline']])]
    return dict(title='تقرير المبيعات والمصاريف', generated_at=datetime.utcnow().isoformat()+'Z',
        notes=[f"الفترة: {data['start_date']} — {data['end_date']}",
            'التواريخ والأوقات حسب التوقيت المحلي للفترة المختارة. المبالغ بالدينار العراقي.',
            'المصاريف التشغيلية لا تشمل التوريد؛ تكلفة البضاعة المباعة محسوبة مرة واحدة.',
            'نهاية الفترة الزمنية غير مشمولة. الرواتب والالتزامات تدخل المصاريف بتاريخ الدفع.',
            'الخانة الفارغة تعني أن التفصيل غير محفوظ في الطلب القديم؛ لا تعني صفراً.'],
        filter=data.get('resolved_filter'), sections=sections, orders=order_details(data['sales'], costs, profits))


def safe_cell(value):
    # CSV and workbook exports must never turn product names into formulas.
    if isinstance(value, str) and value.lstrip().startswith(('=', '+', '-', '@', '\t', '\r')):
        return "'" + value
    return value


def encode_document(document, fmt):
    if fmt == 'json': return json.dumps(document, ensure_ascii=False, indent=2).encode('utf-8'), 'application/json'
    if fmt == 'csv':
        out = io.StringIO(newline='')
        writer = csv.writer(out)
        writer.writerow([document['title']])
        for note in document['notes']: writer.writerow([safe_cell(note)])
        for s in document['sections']:
            writer.writerow([])
            writer.writerow([s['name']])
            writer.writerow(s['columns'])
            writer.writerows([[safe_cell(v) for v in row] for row in s['rows']])
        return out.getvalue().encode('utf-8-sig'), 'text/csv; charset=utf-8'
    if fmt == 'xlsx':
        from xlsx_reports import encode_xlsx
        return encode_xlsx(document), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    if fmt != 'pdf': raise ValueError('صيغة التصدير غير مدعومة.')
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, LongTable, TableStyle
    from reportlab.lib import colors
    import arabic_reshaper
    from bidi.algorithm import get_display
    if 'ReportArabic' not in pdfmetrics.getRegisteredFontNames():
        from flask import current_app
        font = Path(current_app.config.get('REPORT_FONT_PATH') or Path(__file__).resolve().parent.parent/'frontend/assets/fonts/NotoSansArabic.ttf')
        pdfmetrics.registerFont(TTFont('ReportArabic', str(font)))
    style = ParagraphStyle('Arabic', fontName='ReportArabic', fontSize=8, leading=14, alignment=2)
    heading = ParagraphStyle('Title', parent=style, fontSize=16, leading=24, spaceAfter=12)
    def para(value, width, st=style):
        # Wrap logical text first, then shape each line, preserving RTL line order.
        lines, current = [], ''
        for word in str('' if value is None else value).replace('\n',' \n ').split(' '):
            trial = (current+' '+word).strip()
            shaped = get_display(arabic_reshaper.reshape(trial))
            if word == '\n' or (current and pdfmetrics.stringWidth(shaped, 'ReportArabic', st.fontSize) > width-12):
                lines.append(current); current = '' if word == '\n' else word
            else: current = trial
        lines.append(current)
        return Paragraph('<br/>'.join(escape(get_display(arabic_reshaper.reshape(line))) for line in lines), st)
    out = io.BytesIO()
    page = landscape(A4); usable = page[0]-64
    story=[para(document['title'],usable,heading)]
    for note in document['notes']: story += [para(note,usable), Spacer(1,6)]
    for s in document['sections']:
        story += [Spacer(1,14),para(s['name'],usable,heading)]
        if not s['rows']: story.append(para('لا توجد سجلات ضمن الفترة',usable)); continue
        widths=[usable/len(s['columns'])]*len(s['columns'])
        rows=[[para(v,widths[0]) for v in reversed(s['columns'])]]
        rows += [[para(v,widths[0]) for v in reversed(row)] for row in s['rows']]
        table=LongTable(rows,colWidths=widths,repeatRows=1,hAlign='RIGHT')
        table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#DDF1FA')),
            ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor('#F3F6FA')]),
            ('VALIGN',(0,0),(-1,-1),'TOP'),('GRID',(0,0),(-1,-1),.3,colors.HexColor('#CAD6DF')),
            ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6)]))
        story.append(table)
    def footer(canvas, doc):
        canvas.setFont('ReportArabic',8);canvas.drawRightString(page[0]-32,18,str(doc.page))
    SimpleDocTemplate(out,pagesize=page,rightMargin=32,leftMargin=32,topMargin=28,bottomMargin=32,title=document['title']).build(story,onFirstPage=footer,onLaterPages=footer)
    return out.getvalue(),'application/pdf'


def install_exports(app, get_stats):
    POLICY.update(export_report=MANAGERS, export_sale=set(['cashier',*MANAGERS]), export_cart=set(['cashier',*MANAGERS]))
    def download(document, name):
        fmt=request.args.get('format','pdf')
        try: raw,mime=encode_document(document,fmt)
        except ValueError as error: return failure(str(error),400)
        response = send_file(io.BytesIO(raw),mimetype=mime,as_attachment=True,download_name=f'{name}.{fmt}',max_age=0)
        response.direct_passthrough = False
        response.headers['Cache-Control'] = 'private, no-store'
        return response
    @app.get('/api/reports/export')
    def export_report():
        return download(report_document(get_stats().get_json()),'sales-report')
    @app.get('/api/sales/<int:sale_id>/export')
    def export_sale(sale_id):
        sale=db.session.get(Sale,sale_id)
        if not sale: return failure('الطلب غير موجود.',404)
        if not has_permission('sales.view_all') and sale.cashier_id != g.current_user.id: return failure('يمكنك تصدير طلباتك فقط.')
        d=sale.to_dict()
        d['created_at']=sale.created_at.isoformat()+'Z' if sale.created_at else ''
        return download(dict(title=f'تفاصيل الطلب #{sale.id}',notes=['طلب مكتمل • التواريخ بتوقيت UTC'],sections=sale_sections([d],has_permission('financial.costs'),has_permission('financial.profit')),orders=order_details([d],has_permission('financial.costs'),has_permission('financial.profit'))),f'order-{sale.id}')
    @app.post('/api/cart/export')
    def export_cart():
        try:
            d=request.get_json() or {}
            items=normalized_items(d)
            if not items: raise ValueError('السلة فارغة.')
            discount=number(d.get('global_discount',0))
            gross=sum(price*q for _,_,price,_,q in items)
            before=sum((price-disc)*q for _,_,price,disc,q in items)
            cost=sum(p.purchase_price*q for p,_,_,_,q in items)
            if before-discount < 0 or (before==0 and discount!=0): raise ValueError('الخصم غير صالح.')
            lines=[]
            for p,qty,price,disc,q in items:
                net=(price-disc)*q
                net-=discount*net/before if before else 0
                lines.append(dict(product_name=p.name,quantity=qty,is_weight=p.is_weight,weight_unit_grams=p.weight_unit_grams,
                    unit_selling_price=price,unit_purchase_price=p.purchase_price,gross_amount=round(price*q,2),discount_amount=round(price*q-net,2),total_price=round(net,2),total_purchase_cost=round(p.purchase_price*q,2),profit=round(net-p.purchase_price*q,2)))
            sale=dict(id='مسودة',order_type='draft',created_at=datetime.utcnow().isoformat()+'Z',cashier_name=g.current_user.full_name,payment_method='غير مدفوع',
                total_selling_amount=round(gross,2),total_discount=round(gross-before+discount,2),total_purchase_cost=round(cost,2),net_profit=round(before-discount-cost,2),items=lines)
            return download(dict(title='مسودة سلة / طلب غير مكتمل',notes=['هذه مسودة وليست إثبات دفع. لا تغيّر المخزون أو تسجل مبيعات.','التواريخ بتوقيت UTC.'],sections=sale_sections([sale],has_permission('financial.costs'),has_permission('financial.profit')),orders=order_details([sale],has_permission('financial.costs'),has_permission('financial.profit'))),'cart-draft')
        except (ValueError,TypeError) as error: return failure(str(error),400)
