from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
import json

db = SQLAlchemy()

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    full_name = db.Column(db.String(120), nullable=False)
    role = db.Column(db.String(20), default='cashier') # 'developer', 'owner', 'admin', 'cashier'
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'username': self.username,
            'full_name': self.full_name,
            'role': self.role,
            'is_active': self.is_active,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else ''
        }

class AuthSession(db.Model):
    __tablename__ = 'auth_sessions'
    token_hash = db.Column(db.String(64), primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)


class OTPCode(db.Model):
    __tablename__ = 'otp_codes'

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), nullable=False)
    code = db.Column(db.String(6), nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    is_used = db.Column(db.Boolean, default=False)

class Product(db.Model):
    __tablename__ = 'products'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(150), nullable=False)
    image_url = db.Column(db.String(500), nullable=True)
    purchase_price = db.Column(db.Float, default=0.0)
    selling_price = db.Column(db.Float, default=0.0)
    stock_quantity = db.Column(db.Float, default=0.0)
    category = db.Column(db.String(80), default='عام')
    barcode = db.Column(db.String(100), unique=True, nullable=True)
    is_weight = db.Column(db.Boolean, default=False)
    weight_unit_grams = db.Column(db.Integer, default=1000)
    weight_increment_step = db.Column(db.Float, default=100.0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    @property
    def unit_profit(self):
        return self.selling_price - self.purchase_price

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'image_url': self.image_url or '',
            'purchase_price': self.purchase_price,
            'selling_price': self.selling_price,
            'unit_profit': round(self.unit_profit, 2),
            'stock_quantity': self.stock_quantity,
            'is_weight': self.is_weight,
            'weight_unit_grams': self.weight_unit_grams,
            'weight_increment_step': self.weight_increment_step,
            'category': self.category,
            'barcode': self.barcode or '',
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else ''
        }

class Sale(db.Model):
    __tablename__ = 'sales'

    id = db.Column(db.Integer, primary_key=True)
    checkout_key = db.Column(db.String(80), unique=True, nullable=True)
    order_type = db.Column(db.String(20), nullable=True)
    table_name = db.Column(db.String(50), nullable=True)
    cashier_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True)
    cashier_name = db.Column(db.String(120), default='كاشير')
    total_purchase_cost = db.Column(db.Float, default=0.0)
    total_selling_amount = db.Column(db.Float, default=0.0)
    total_discount = db.Column(db.Float, default=0.0)
    net_profit = db.Column(db.Float, default=0.0)
    payment_method = db.Column(db.String(50), default='نقداً')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    items = db.relationship('SaleItem', backref='sale', lazy=True, cascade="all, delete-orphan")

    def to_dict(self):
        return {
            'id': self.id,
            'cashier_id': self.cashier_id,
            'order_type': self.order_type,
            'table_name': self.table_name,
            'cashier_name': self.cashier_name,
            'total_purchase_cost': round(self.total_purchase_cost, 2),
            'total_selling_amount': round(self.total_selling_amount, 2),
            'total_discount': round(self.total_discount, 2),
            'net_profit': round(self.net_profit, 2),
            'payment_method': self.payment_method,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else '',
            'items': [item.to_dict() for item in self.items]
        }

class SaleItem(db.Model):
    __tablename__ = 'sale_items'

    id = db.Column(db.Integer, primary_key=True)
    sale_id = db.Column(db.Integer, db.ForeignKey('sales.id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('products.id'), nullable=True)
    product_name = db.Column(db.String(150), nullable=False)
    quantity = db.Column(db.Float, default=1.0)
    is_weight = db.Column(db.Boolean, nullable=True)
    weight_unit_grams = db.Column(db.Integer, nullable=True)
    unit_purchase_price = db.Column(db.Float, default=0.0)
    unit_selling_price = db.Column(db.Float, default=0.0)
    discount = db.Column(db.Float, default=0.0)
    total_price = db.Column(db.Float, default=0.0)
    profit = db.Column(db.Float, default=0.0)

    def to_dict(self):
        effective = None
        if self.is_weight is False:
            effective = self.quantity
        elif self.is_weight is True and self.weight_unit_grams:
            effective = self.quantity / self.weight_unit_grams
        return {
            'id': self.id,
            'product_id': self.product_id,
            'product_name': self.product_name,
            'quantity': self.quantity,
            'is_weight': self.is_weight,
            'weight_unit_grams': self.weight_unit_grams,
            'gross_amount': round(self.unit_selling_price * effective, 2) if effective is not None else None,
            'discount_amount': round(self.discount * effective, 2) if effective is not None else None,
            'total_purchase_cost': round(self.total_price - self.profit, 2),
            'unit_purchase_price': self.unit_purchase_price,
            'unit_selling_price': self.unit_selling_price,
            'discount': self.discount,
            'total_price': round(self.total_price, 2),
            'profit': round(self.profit, 2)
        }

class Expense(db.Model):
    __tablename__ = 'expenses'

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(150), nullable=False)
    amount = db.Column(db.Float, nullable=False)
    category = db.Column(db.String(80), default='عام')
    notes = db.Column(db.String(255), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    created_by = db.Column(db.String(120), default='المدير')
    source = db.Column(db.String(20), default='manual')
    source_key = db.Column(db.String(100), unique=True, nullable=True)

    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'amount': round(self.amount, 2),
            'category': self.category,
            'notes': self.notes or '',
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else '',
            'created_by': self.created_by
            , 'source': self.source or 'manual'
        }

class RestockHistory(db.Model):
    __tablename__ = 'restock_history'

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('products.id'), nullable=False)
    quantity = db.Column(db.Float, nullable=False)
    purchase_price = db.Column(db.Float, nullable=False)
    note = db.Column(db.String(255), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'product_id': self.product_id,
            'quantity': self.quantity,
            'purchase_price': round(self.purchase_price, 2),
            'note': self.note or '',
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else ''
        }

class Table(db.Model):
    __tablename__ = 'tables'

    id = db.Column(db.Integer, primary_key=True)
    table_number = db.Column(db.Integer, unique=True, nullable=False)
    name = db.Column(db.String(50), nullable=True)
    is_active = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'table_number': self.table_number,
            'name': self.name or f'طاولة {self.table_number}',
            'is_active': self.is_active,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else ''
        }

class ActiveOrder(db.Model):
    __tablename__ = 'active_orders'

    id = db.Column(db.Integer, primary_key=True)
    table_id = db.Column(db.Integer, db.ForeignKey('tables.id'), nullable=True)
    order_type = db.Column(db.String(20), default='table') # 'table' or 'direct'
    cashier_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True)
    total_amount = db.Column(db.Float, default=0.0)
    cart_state = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    items = db.relationship('ActiveOrderItem', backref='active_order', lazy=True, cascade="all, delete-orphan")
    table = db.relationship('Table', backref=db.backref('active_order', uselist=False))

    def to_dict(self):
        return {
            'id': self.id,
            'table_id': self.table_id,
            'order_type': self.order_type,
            'cart_state': json.loads(self.cart_state) if self.cart_state else None,
            'total_amount': round(self.total_amount, 2),
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else '',
            'items': [item.to_dict() for item in self.items]
        }

class ActiveOrderItem(db.Model):
    __tablename__ = 'active_order_items'

    id = db.Column(db.Integer, primary_key=True)
    active_order_id = db.Column(db.Integer, db.ForeignKey('active_orders.id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('products.id'), nullable=True)
    product_name = db.Column(db.String(150), nullable=False)
    quantity = db.Column(db.Float, default=1.0)
    unit_price = db.Column(db.Float, default=0.0)
    total_price = db.Column(db.Float, default=0.0)

    def to_dict(self):
        return {
            'id': self.id,
            'product_id': self.product_id,
            'product_name': self.product_name,
            'quantity': self.quantity,
            'unit_price': self.unit_price,
            'total_price': round(self.total_price, 2)
        }

