from core_system import core
from models import db, Table, ActiveOrder, ActiveOrderItem, Product

@core.action(name="get_tables", description="يجلب جميع الطاولات مع أسعار طلباتها النشطة")
def get_tables():
    tables = Table.query.order_by(Table.table_number.asc()).all()
    result = []
    for t in tables:
        total_price = 0.0
        if t.is_active:
            order = ActiveOrder.query.filter_by(table_id=t.id).first()
            if order:
                items = ActiveOrderItem.query.filter_by(active_order_id=order.id).all()
                for i in items:
                    total_price += (i.unit_price * i.quantity)
        result.append({
            'id': t.id,
            'table_number': t.table_number,
            'name': t.name or f"طاولة {t.table_number}",
            'is_active': t.is_active,
            'total_price': total_price
        })
    return result

@core.action(name="create_tables", description="يضيف مجموعة من الطاولات الجديدة للمطعم")
def create_tables(count: int):
    current_count = Table.query.count()
    new_tables = []
    for i in range(count):
        t_num = current_count + i + 1
        new_table = Table(table_number=t_num, name=f"طاولة {t_num}")
        db.session.add(new_table)
        new_tables.append(new_table)
    db.session.commit()
    return {"status": "success", "added": count}

@core.action(name="clear_all_tables", description="يحذف جميع الطاولات والطلبات النشطة (للتهيئة)")
def clear_all_tables():
    ActiveOrderItem.query.delete()
    ActiveOrder.query.delete()
    Table.query.delete()
    db.session.commit()
    return {"status": "success"}
