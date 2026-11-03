"""Validated table drafts and atomic sales; quantities are grams for weighted products."""
import json
import math
from flask import request, jsonify, g
from sqlalchemy.exc import IntegrityError
from models import db, Product, Sale, SaleItem, Table, ActiveOrder, ActiveOrderItem
from security import failure

def number(value):
    try:
        result = float(value)
    except (TypeError, ValueError):
        raise ValueError('أدخل أرقاماً صحيحة للكميات والأسعار.')
    if not math.isfinite(result):
        raise ValueError('المبالغ والكميات يجب أن تكون أرقاماً محدودة.')
    return result

def normalized_items(data):
    items = data.get('items', [])
    if not isinstance(items, list) or len(items) > 1000:
        raise ValueError('قائمة المنتجات غير صالحة.')
    result = []
    for item in items:
        product = db.session.get(Product, item.get('product_id'))
        if not product:
            raise ValueError('أحد المنتجات لم يعد موجوداً. حدّث السلة.')
        qty = number(item.get('quantity', 0))
        price = number(item.get('unit_selling_price', product.selling_price))
        discount = number(item.get('discount', 0))
        if qty <= 0 or price < 0 or discount > price:
            raise ValueError('الكمية يجب أن تكون موجبة، والسعر النهائي لا يمكن أن يكون سالباً.')
        effective = qty / product.weight_unit_grams if product.is_weight and product.weight_unit_grams > 0 else qty
        result.append((product, qty, price, discount, effective))
    return result

def save_table_transaction(table_id):
    table = db.session.get(Table, table_id)
    if not table:
        return failure('الطاولة غير موجودة.', 404)
    try:
        data = request.get_json() or {}
        items = normalized_items(data)
        extra_discount = number(data.get('global_discount', 0))
        total = sum((p - d) * q for _, _, p, d, q in items) - extra_discount
        if total < 0:
            raise ValueError('الخصم أكبر من مجموع الطلب.')
        order = ActiveOrder.query.filter_by(table_id=table_id).first()
        if not items:
            if order:
                db.session.delete(order)
            table.is_active = False
            db.session.commit()
            return jsonify(status='success')
        if not order:
            order = ActiveOrder(table_id=table_id)
            db.session.add(order)
            db.session.flush()
        else:
            for item in list(order.items):
                db.session.delete(item)
        order.cashier_id = g.current_user.id
        snapshots = []
        for product, qty, price, discount, effective in items:
            db.session.add(ActiveOrderItem(active_order_id=order.id, product_id=product.id,
                product_name=product.name, quantity=qty, unit_price=price - discount,
                total_price=(price - discount) * effective))
            snapshots.append({'product_id': product.id, 'product_name': product.name,
                'quantity': qty, 'unit_selling_price': price, 'discount': discount,
                'is_weight': product.is_weight, 'weight_unit_grams': product.weight_unit_grams})
        order.cart_state = json.dumps({'items': snapshots, 'global_discount': extra_discount})
        order.total_amount = total
        table.is_active = True
        db.session.commit()
        return jsonify(status='success')
    except (ValueError, TypeError, AttributeError) as error:
        db.session.rollback()
        return failure(str(error), 400)

def create_sale_transaction():
    data = request.get_json() or {}
    key = data.get('checkout_key')
    if not isinstance(key, str) or not key or len(key) > 80:
        return failure('حدّث الواجهة ثم أعد المحاولة.', 400)
    existing = Sale.query.filter_by(checkout_key=key).first()
    if existing:
        if existing.cashier_id != g.current_user.id:
            return failure('معرّف البيع مستخدم بالفعل.', 409)
        return jsonify(status='success', sale=existing.to_dict())
    try:
        items = normalized_items(data)
        if not items:
            raise ValueError('السلة فارغة.')
        discount = number(data.get('global_discount', 0))
        table_id = data.get('table_id')
        table = db.session.get(Table, table_id) if table_id else None
        if table_id and (not table or not table.is_active):
            return failure('هذه الطاولة غير نشطة. أعد فتح الطاولة.', 409)
        gross = sum(price * effective for _, _, price, _, effective in items)
        item_discounts = sum(d * q for _, _, _, d, q in items)
        cost = sum(product.purchase_price * q for product, _, _, _, q in items)
        revenue = gross - item_discounts - discount
        if gross == item_discounts and discount != 0:
            raise ValueError('لا يمكن توزيع تعديل المجموع على طلب قيمته صفر.')
        if revenue < 0:
            raise ValueError('الخصم أكبر من مجموع الطلب.')
        sale = Sale(checkout_key=key, cashier_id=g.current_user.id,
            order_type='table' if table else 'direct',
            table_name=(table.name or f'طاولة {table.table_number}') if table else None,
            cashier_name=g.current_user.full_name, payment_method=data.get('payment_method') or 'نقداً',
            total_purchase_cost=cost, total_selling_amount=gross,
            total_discount=item_discounts + discount, net_profit=revenue - cost)
        db.session.add(sale)
        db.session.flush()
        for product, qty, price, line_discount, effective in items:
            changed = db.session.execute(db.update(Product).where(
                Product.id == product.id, Product.stock_quantity >= qty
            ).values(stock_quantity=Product.stock_quantity - qty))
            if changed.rowcount != 1:
                raise ValueError(f'المخزون غير كافٍ للمنتج: {product.name}')
            line_total = (price - line_discount) * effective
            # Allocate order-level discounts to lines so product reports sum to the sale.
            share = discount * (line_total / (gross - item_discounts)) if gross != item_discounts else 0
            db.session.add(SaleItem(sale_id=sale.id, product_id=product.id,
                is_weight=product.is_weight, weight_unit_grams=product.weight_unit_grams if product.is_weight else None,
                product_name=product.name, quantity=qty, unit_purchase_price=product.purchase_price,
                unit_selling_price=price, discount=line_discount + share / effective,
                total_price=line_total - share, profit=line_total - share - product.purchase_price * effective))
        if table:
            order = ActiveOrder.query.filter_by(table_id=table_id).first()
            if order:
                db.session.delete(order)
            table.is_active = False
        db.session.commit()
        return jsonify(status='success', sale=sale.to_dict()), 201
    except IntegrityError:
        db.session.rollback()
        existing = Sale.query.filter_by(checkout_key=key, cashier_id=g.current_user.id).first()
        if existing:
            return jsonify(status='success', sale=existing.to_dict())
        return failure('تعارض أثناء حفظ البيع. أعد المحاولة.', 409)
    except (ValueError, TypeError, AttributeError) as error:
        db.session.rollback()
        return failure(str(error), 400)

