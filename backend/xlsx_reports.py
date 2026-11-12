"""Readable RTL Excel reports, with an order index linked to full order blocks."""
import io
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.pagebreak import Break

def encode_xlsx(document):
    from report_exports import safe_cell
    wb = Workbook(); wb.remove(wb.active)
    blue='007FAE'; dark='17324D'; pale='EDF6FA'
    money='#,##0.00;[Red](#,##0.00);"—"'
    integer='#,##0.###;[Red](#,##0.###);"—"'
    def setup(ws):
        ws.sheet_view.rightToLeft=True; ws.sheet_view.showGridLines=False
        ws.sheet_view.zoomScale=90
        ws.sheet_properties.pageSetUpPr.fitToPage=True
        ws.page_setup.orientation='landscape';ws.page_setup.paperSize=ws.PAPERSIZE_A3
        ws.page_setup.fitToWidth=1;ws.page_setup.fitToHeight=0
        ws.oddFooter.center.text='صفحة &P من &N'
        ws.oddFooter.right.text='نظام الكاشير • د.ع'
    def title(ws, text, width):
        row=ws.max_row+1 if ws.cell(1,1).value is not None else 1
        ws.cell(row,1,safe_cell(text));ws.merge_cells(start_row=row,start_column=1,end_row=row,end_column=width)
        cell=ws.cell(row,1);cell.font=Font(name='Arial',size=18,bold=True,color='FFFFFF');cell.fill=PatternFill('solid',fgColor=dark)
        cell.alignment=Alignment(horizontal='right',vertical='center',readingOrder=2,wrap_text=True);ws.row_dimensions[row].height=38
        return row
    def header(ws, labels):
        ws.append(labels);r=ws.max_row
        for c in ws[r]:
            c.font=Font(name='Arial',bold=True,color='FFFFFF',size=11);c.fill=PatternFill('solid',fgColor=blue)
            c.alignment=Alignment(horizontal='right',vertical='center',readingOrder=2,wrap_text=True)
        ws.row_dimensions[r].height=34
        return r
    def rows(ws, labels, values):
        for index, values_row in enumerate(values):
            ws.append([safe_cell(v) for v in values_row]);r=ws.max_row
            for c in ws[r]:
                c.font=Font(name='Arial',size=11,color=dark)
                c.fill=PatternFill('solid',fgColor=pale if index%2==0 else 'FFFFFF')
                c.alignment=Alignment(horizontal='right',vertical='center',wrap_text=True,readingOrder=2)
                c.border=Border(bottom=Side(style='hair',color='D9E7ED'))
                if isinstance(c.value,(float,int)):
                    label=labels[c.column-1]
                    c.number_format=integer if any(x in label for x in ['الطلب','الكمية','عدد']) else money
            ws.row_dimensions[r].height=34
    def widths(ws,labels):
        for i,label in enumerate(labels,1):
            width=40 if label in ['المنتج','العنوان','ملاحظات','البند'] else 26 if 'التاريخ' in label or 'الكاشير' in label else 19
            ws.column_dimensions[get_column_letter(i)].width=width
    for section in document['sections']:
        ws=wb.create_sheet(section['name'][:31]);setup(ws)
        columns=section['columns'];n=max(2,len(columns))
        title(ws,document['title']+' • '+section['name'],n)
        for note in document['notes']:
            ws.append([safe_cell(note)]);r=ws.max_row
            ws.merge_cells(start_row=r,start_column=1,end_row=r,end_column=n)
            ws.cell(r,1).alignment=Alignment(horizontal='right',vertical='center',readingOrder=2,wrap_text=True)
            ws.cell(r,1).font=Font(name='Arial',size=11,color='52677B')
            ws.row_dimensions[r].height=44 if n==2 else 30
        h=header(ws,columns);rows(ws,columns,section['rows']);widths(ws,columns)
        if section['name']=='الملخص':ws.column_dimensions['A'].width=53;ws.column_dimensions['B'].width=32
        ws.freeze_panes=f'A{h+1}';ws.auto_filter.ref=f'A{h}:{get_column_letter(n)}{ws.max_row}'
        ws.print_title_rows=f'{h}:{h}';ws.print_area=f'A1:{get_column_letter(n)}{ws.max_row}'
        ws.sheet_properties.tabColor=blue
        if not section['rows']:
            ws.append(['لا توجد سجلات ضمن الفترة المحددة.']);ws.row_dimensions[ws.max_row].height=30
    if document.get('orders'):
        ws=wb.create_sheet('تفاصيل كل طلب',2);setup(ws);anchors={}
        for order in document['orders']:
            if anchors:
                ws.append([]);ws.append([])
                ws.row_breaks.append(Break(id=ws.max_row))
            labels=order['items']['columns'];n=max(2,len(labels))
            anchor=title(ws,f"تفاصيل الطلب #{order['id']}",n);anchors[str(order['id'])]=anchor
            for key,value in order['summary']:
                ws.append([key,safe_cell(value)]);r=ws.max_row
                ws.cell(r,1).font=Font(name='Arial',bold=True,color=dark)
                ws.cell(r,1).alignment=Alignment(horizontal='right',readingOrder=2)
                ws.merge_cells(start_row=r,start_column=2,end_row=r,end_column=n)
                ws.cell(r,2).alignment=Alignment(horizontal='right',readingOrder=2,wrap_text=True)
                if isinstance(value,(int,float)):ws.cell(r,2).number_format=integer if 'عدد' in key or key=='الطلب' else money
                ws.row_dimensions[r].height=27
            header(ws,labels);rows(ws,labels,order['items']['rows']);widths(ws,labels)
            ws.append(['الرجوع إلى فهرس الطلبات']);r=ws.max_row
            ws.cell(r,1).hyperlink="#'الطلبات'!A1";ws.cell(r,1).font=Font(name='Arial',color=blue,underline='single')
        ws.freeze_panes='A2';ws.print_area=f'A1:{get_column_letter(ws.max_column)}{ws.max_row}'
        index=wb['الطلبات']
        for row in index.iter_rows():
            if str(row[0].value) in anchors:
                row[0].hyperlink=f"#'تفاصيل كل طلب'!A{anchors[str(row[0].value)]}"
                row[0].font=Font(name='Arial',color=blue,bold=True,underline='single')
    out=io.BytesIO();wb.save(out);return out.getvalue()
