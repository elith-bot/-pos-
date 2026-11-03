import os
import random
from datetime import datetime, timedelta
from werkzeug.exceptions import BadRequest
from report_filters import report_window
from flask import Flask, request, jsonify, g
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy.exc import OperationalError
from config import Config

from models import db, User, OTPCode, Product, Sale, SaleItem, Expense, RestockHistory, Table, ActiveOrder, ActiveOrderItem
from core_system import core
import actions
from security import install_security, issue_session, manageable, revoke, failure
from transactions import create_sale_transaction, save_table_transaction
from transactions import number
from hr_finance import install_hr_finance
from report_exports import install_exports

def create_app(test_config=None):
    app = Flask(__name__)
    app.config.from_object(Config)
    if test_config:
        app.config.update(test_config)

    CORS(app)
    db.init_app(app)
    install_security(app)
    install_hr_finance(app)

    with app.app_context():
        try:
            db.create_all()
            for statement in [
                'ALTER TABLE hr_staff ADD COLUMN user_id INTEGER REFERENCES users(id)',
                'CREATE UNIQUE INDEX IF NOT EXISTS ix_hr_staff_user ON hr_staff (user_id)',
                "ALTER TABLE hr_payroll ADD COLUMN calculation TEXT DEFAULT '{}'",
                "ALTER TABLE expenses ADD COLUMN source VARCHAR(20) DEFAULT 'manual'",
                'ALTER TABLE expenses ADD COLUMN source_key VARCHAR(100)',
                'CREATE UNIQUE INDEX IF NOT EXISTS ix_expenses_source_key ON expenses (source_key)',
                'ALTER TABLE active_orders ADD COLUMN cart_state TEXT',
                'ALTER TABLE sales ADD COLUMN checkout_key VARCHAR(80)',
                'ALTER TABLE sales ADD COLUMN order_type VARCHAR(20)',
                'ALTER TABLE sales ADD COLUMN table_name VARCHAR(50)',
                'ALTER TABLE sale_items ADD COLUMN is_weight BOOLEAN',
                'ALTER TABLE sale_items ADD COLUMN weight_unit_grams INTEGER',
                'CREATE UNIQUE INDEX IF NOT EXISTS ix_sales_checkout_key ON sales (checkout_key)',
            ]:
                try:
                    db.session.execute(db.text(statement))
                    db.session.commit()
                except Exception:
                    db.session.rollback()
            
            # Simple migration to add columns if they don't exist
            try:
                db.session.execute(db.text('ALTER TABLE products ADD COLUMN is_weight BOOLEAN DEFAULT FALSE'))
                db.session.commit()
            except Exception:
                db.session.rollback()

            try:
                db.session.execute(db.text('ALTER TABLE products ADD COLUMN weight_unit_grams INTEGER DEFAULT 1000'))
                db.session.commit()
            except Exception:
                db.session.rollback()

            try:
                db.session.execute(db.text('ALTER TABLE products ADD COLUMN weight_increment_step FLOAT DEFAULT 100.0'))
                db.session.commit()
            except Exception:
                db.session.rollback()
                
            try:
                db.session.execute(db.text('ALTER TABLE products ADD COLUMN barcode VARCHAR(100) DEFAULT NULL'))
                db.session.commit()
            except Exception:
                db.session.rollback()

            try:
                db.session.execute(db.text('ALTER TABLE restock_history ADD COLUMN note VARCHAR(255) DEFAULT NULL'))
                db.session.commit()
            except Exception:
                db.session.rollback()

            # Seed initial Developer account if users table is empty
            if User.query.count() == 0 : 
                dev = User(
                    username='admin',
                    password_hash=generate_password_hash('admin123'),
                    full_name='المطور الرئيسي',
                    role='developer',
                    is_active=True
                )
                db.session.add(dev)
     
                # Seed sample products
                sample_products = [
                    Product(name='مشروب بيبسي 330 مل', purchase_price=500, selling_price=750, stock_quantity=50, category='مشروبات'),
                    Product(name='شيبس ليز بالملح 50غم', purchase_price=750, selling_price=1000, stock_quantity=40, category='سناكس'),
                    Product(name='ماء معدني 500 مل', purchase_price=250, selling_price=500, stock_quantity=100, category='مشروبات'),
                    Product(name='شوكولاتة جالاكسي سادة', purchase_price=1000, selling_price=1500, stock_quantity=30, category='حلويات'),
                ]
                for p in sample_products:
                    db.session.add(p)
                    db.session.flush()
                    db.session.add(RestockHistory(
                        product_id=p.id,
                        quantity=p.stock_quantity,
                        purchase_price=p.purchase_price,
                        note='أول عملية شراء (إضافة المنتج)',
                        created_at=p.created_at or datetime.utcnow()
                    ))

                db.session.commit()
                print("Seeded default developer user and sample products.")

            # Ensure all existing products have an initial purchase record in RestockHistory
            all_prods = Product.query.all()
            for p in all_prods:
                if RestockHistory.query.filter_by(product_id=p.id).count() == 0:
                    db.session.add(RestockHistory(
                        product_id=p.id,
                        quantity=p.stock_quantity,
                        purchase_price=p.purchase_price,
                        note='أول عملية شراء (إضافة المنتج)',
                        created_at=p.created_at or datetime.utcnow()
                    ))
            db.session.commit()
        except Exception as e:
            print(f"Database initialization warning: {e}")

    @app.route('/api/health', methods=['GET'])
    def health_check():
        db_connected = False
        try:
            db.session.execute(db.select(1))
            db_connected = True
        except Exception as e:
            pass

        return jsonify({
            'status': 'success',
            'server': 'online',
            'db_type': app.config['DATABASE_TYPE'],
            'db_connected': db_connected
        })

    @app.errorhandler(BadRequest)
    def bad_report_request(error):
        return failure(error.description, 400)

    @app.errorhandler(OperationalError)
    def handle_db_error(e):
        try:
            db.session.rollback()
        except Exception:
            pass
        return jsonify({
            'status': 'error',
            'message': 'تعذر الاتصال بقاعدة بيانات MySQL. يرجى التأكد من تشغيل خادم MySQL أو التبديل لـ SQLite في الإعدادات.'
        }), 503


    # ================= AUTHENTICATION APIs =================
    @app.route('/api/auth/register', methods=['POST'])
    def register():
        data = request.get_json() or {}
        username = data.get('username', '').strip()
        password = data.get('password', '')
        full_name = data.get('full_name', '').strip()

        if not username or len(password) < 8 or not full_name:
            return jsonify({'status': 'error', 'message': 'الاسم واسم المستخدم مطلوبان وكلمة المرور 8 أحرف على الأقل'}), 400

        if User.query.filter_by(username=username).first():
            return jsonify({'status': 'error', 'message': 'اسم المستخدم مسجل مسبقاً'}), 400

        # Default role for new signups is cashier
        new_user = User(
            username=username,
            password_hash=generate_password_hash(password),
            full_name=full_name,
            role='cashier',
            is_active=True
        )
        db.session.add(new_user)
        db.session.commit()

        return jsonify({
            'status': 'success',
            'message': 'تم إنشاء الحساب بنجاح كـ "كاشير"',
            'user': new_user.to_dict()
        }), 201

    @app.route('/api/auth/login', methods=['POST'])
    def login():
        data = request.get_json() or {}
        username = data.get('username', '').strip()
        password = data.get('password', '')

        user = User.query.filter_by(username=username).first()
        if not user or not check_password_hash(user.password_hash, password):
            return jsonify({'status': 'error', 'message': 'اسم المستخدم أو كلمة المرور غير صحيحة'}), 401

        if not user.is_active:
            return jsonify({'status': 'error', 'message': 'الحساب معطل من قبل الإدارة'}), 403

        return jsonify({
            'status': 'success',
            'message': 'تم تسجيل الدخول بنجاح',
            'token': issue_session(user),
            'user': user.to_dict()
        })

    @app.route('/api/auth/request-otp', methods=['POST'])
    def request_otp():
        data = request.get_json() or {}
        username = data.get('username', '').strip()

        user = User.query.filter_by(username=username).first()
        if not user:
            return jsonify({'status': 'error', 'message': 'اسم المستخدم غير موجود'}), 44

        code = str(random.randint(100000, 999999))
        expires_at = datetime.utcnow() + timedelta(minutes=10)

        otp = OTPCode(username=username, code=code, expires_at=expires_at)
        db.session.add(otp)
        db.session.commit()

        return jsonify({
            'status': 'success',
            'message': f'رمز التحقق OTP الخاص بك هو: {code} (صالح لمدة 10 دقائق)',
            'otp_code': code
        })

    @app.route('/api/auth/reset-password', methods=['POST'])
    def reset_password():
        data = request.get_json() or {}
        username = data.get('username', '').strip()
        code = data.get('code', '').strip()
        new_password = data.get('new_password', '')

        otp = OTPCode.query.filter_by(username=username, code=code, is_used=False).order_by(OTPCode.id.desc()).first()
        if not otp or otp.expires_at < datetime.utcnow():
            return jsonify({'status': 'error', 'message': 'رمز التحقق غير صحيح أو منتهي الصلاحية'}), 400

        user = User.query.filter_by(username=username).first()
        if not user:
            return jsonify({'status': 'error', 'message': 'المستخدم غير موجود'}), 404

        user.password_hash = generate_password_hash(new_password)
        otp.is_used = True
        db.session.commit()

        return jsonify({'status': 'success', 'message': 'تم إعادة تعيين كلمة المرور بنجاح'})

    # ================= EMPLOYEES & USERS APIs =================
    @app.route('/api/users', methods=['GET'])
    def get_users():
        users = User.query.order_by(User.id.asc()).all()
        return jsonify({'status': 'success', 'users': [u.to_dict() for u in users]})

    @app.route('/api/users/<int:user_id>/role', methods=['PUT'])
    def update_user_role(user_id):
        data = request.get_json() or {}
        new_role = data.get('role')
        if new_role not in ['developer', 'owner', 'admin', 'cashier']:
            return jsonify({'status': 'error', 'message': 'دور غير صالح'}), 400

        user = User.query.get(user_id)
        if not user:
            return jsonify({'status': 'error', 'message': 'المستخدم غير موجود'}), 404

        if not manageable(user, new_role):
            return failure('لا يمكنك تعديل حسابك أو إدارة دور مساوٍ أو أعلى من دورك.')
        revoke(user.id)
        user.role = new_role
        db.session.commit()
        return jsonify({'status': 'success', 'message': f'تم تغيير دور المستخدم إلى {new_role}', 'user': user.to_dict()})

    @app.route('/api/users/<int:user_id>/toggle-active', methods=['PUT'])
    def toggle_user_active(user_id):
        user = User.query.get(user_id)
        if not user:
            return jsonify({'status': 'error', 'message': 'المستخدم غير موجود'}), 404

        if not manageable(user):
            return failure('لا يمكنك تعطيل حسابك أو إدارة دور مساوٍ أو أعلى من دورك.')
        revoke(user.id)
        user.is_active = not user.is_active
        db.session.commit()
        return jsonify({'status': 'success', 'message': 'تم تغيير حالة الحساب', 'user': user.to_dict()})

    # ================= PRODUCTS & INVENTORY APIs =================
    @app.route('/api/products', methods=['GET'])
    def get_products():
        query_str = request.args.get('search', '').strip()
        min_price = request.args.get('min_price', type=float)
        max_price = request.args.get('max_price', type=float)
        min_stock = request.args.get('min_stock', type=int)

        q = Product.query

        if query_str:
            # Smart search ignoring spaces and case
            clean_search = f"%{query_str}%"
            q = q.filter(Product.name.ilike(clean_search) | Product.category.ilike(clean_search))

        if min_price is not None:
            q = q.filter(Product.selling_price >= min_price)
        if max_price is not None:
            q = q.filter(Product.selling_price <= max_price)
        if min_stock is not None:
            q = q.filter(Product.stock_quantity >= min_stock)

        products = q.order_by(Product.id.desc()).all()
        return jsonify({'status': 'success', 'count': len(products), 'products': [p.to_dict() for p in products]})

    @app.route('/api/products', methods=['POST'])
    def create_product():
        data = request.get_json() or {}
        name = data.get('name', '').strip()
        if not name:
            return jsonify({'status': 'error', 'message': 'اسم المنتج مطلوب'}), 400
            
        barcode = data.get('barcode', '').strip()
        if not barcode:
            barcode = None

        product = Product(
            name=name,
            image_url=data.get('image_url', ''),
            purchase_price=float(data.get('purchase_price', 0)),
            selling_price=float(data.get('selling_price', 0)),
            stock_quantity=float(data.get('stock_quantity', 0)),
            category=data.get('category', 'عام'),
            barcode=barcode,
            is_weight=bool(data.get('is_weight', False)),
            weight_unit_grams=int(data.get('weight_unit_grams', 1000)),
            weight_increment_step=float(data.get('weight_increment_step', 100.0))
        )
        db.session.add(product)
        db.session.flush() # To get product.id

        # Always log initial purchase record (سجل أول عملية شراء للمنتج)
        restock_log = RestockHistory(
            product_id=product.id,
            quantity=product.stock_quantity,
            purchase_price=product.purchase_price,
            note='أول عملية شراء (إضافة المنتج)',
            created_at=product.created_at or datetime.utcnow()
        )
        db.session.add(restock_log)

        if product.stock_quantity > 0 and product.purchase_price > 0:
            expense = Expense(
                title=f'رصيد بضاعة أولي: {product.name}',
                amount=round(product.stock_quantity / (product.weight_unit_grams if product.is_weight and product.weight_unit_grams > 0 else 1) * product.purchase_price, 2),
                source='inventory',
                category='مشتريات/بضاعة',
                notes=f'رصيد أولي لعدد {product.stock_quantity}',
                created_by='النظام'
            )
            db.session.add(expense)

        db.session.commit()
        return jsonify({'status': 'success', 'message': 'تم إضافة المنتج بنجاح', 'product': product.to_dict()}), 201

    @app.route('/api/products/<int:product_id>', methods=['PUT'])
    def update_product(product_id):
        product = Product.query.get(product_id)
        if not product:
            return jsonify({'status': 'error', 'message': 'المنتج غير موجود'}), 404

        data = request.get_json() or {}
        product.name = data.get('name', product.name)
        product.image_url = data.get('image_url', product.image_url)
        product.purchase_price = float(data.get('purchase_price', product.purchase_price))
        product.selling_price = float(data.get('selling_price', product.selling_price))
        product.stock_quantity = float(data.get('stock_quantity', product.stock_quantity))
        product.category = data.get('category', product.category)
        if 'is_weight' in data:
            product.is_weight = bool(data.get('is_weight'))
        if 'weight_unit_grams' in data:
            product.weight_unit_grams = int(data.get('weight_unit_grams'))
        if 'weight_increment_step' in data:
            product.weight_increment_step = float(data.get('weight_increment_step'))
        if 'barcode' in data:
            barcode = data.get('barcode', '').strip()
            product.barcode = barcode if barcode else None

        db.session.commit()
        return jsonify({'status': 'success', 'message': 'تم تحديث بيانات المنتج', 'product': product.to_dict()})

    @app.route('/api/products/<int:product_id>/restock', methods=['POST'])
    def restock_product(product_id):
        product = Product.query.get(product_id)
        if not product:
            return jsonify({'status': 'error', 'message': 'المنتج غير موجود'}), 404

        data = request.get_json() or {}
        try:
            added_qty = number(data.get('added_quantity', 0))
            for key in ['purchase_price', 'selling_price']:
                if data.get(key) is not None and number(data[key]) < 0:
                    raise ValueError('الأسعار لا يمكن أن تكون سالبة.')
        except ValueError as error:
            return failure(str(error), 400)
        new_purchase_price = data.get('purchase_price')
        new_selling_price = data.get('selling_price')

        if added_qty <= 0:
            return jsonify({'status': 'error', 'message': 'يجب إدخال كمية موجبة للتوريد'}), 400

        product.stock_quantity += added_qty
        if new_purchase_price is not None:
            product.purchase_price = float(new_purchase_price)
        if new_selling_price is not None:
            product.selling_price = float(new_selling_price)

        restock_log = RestockHistory(
            product_id=product.id,
            quantity=added_qty,
            purchase_price=product.purchase_price,
            note='توريد شحنة إضافية'
        )
        db.session.add(restock_log)
        
        expense = Expense(
            title=f'توريد بضاعة: {product.name}',
            amount=round(added_qty / (product.weight_unit_grams if product.is_weight and product.weight_unit_grams > 0 else 1) * product.purchase_price, 2),
            source='inventory',
            category='مشتريات/بضاعة',
            notes=f'توريد عدد {added_qty}',
            created_by='النظام'
        )
        db.session.add(expense)

        db.session.commit()
        return jsonify({'status': 'success', 'message': f'تم توريد {added_qty} قطعة للمخزن بنجاح', 'product': product.to_dict()})

    @app.route('/api/products/<int:product_id>', methods=['DELETE'])
    def delete_product(product_id):
        product = Product.query.get(product_id)
        if not product:
            return jsonify({'status': 'error', 'message': 'المنتج غير موجود'}), 404

        RestockHistory.query.filter_by(product_id=product_id).delete()
        db.session.delete(product)
        db.session.commit()
        return jsonify({'status': 'success', 'message': 'تم حذف المنتج بنجاح'})

    @app.route('/api/products/<int:product_id>/restock-history', methods=['GET'])
    def get_restock_history(product_id):
        product = Product.query.get(product_id)
        if not product:
            return jsonify({'status': 'error', 'message': 'المنتج غير موجود'}), 404

        history = RestockHistory.query.filter_by(product_id=product_id).order_by(RestockHistory.id.desc()).all()
        if not history:
            initial_log = RestockHistory(
                product_id=product.id,
                quantity=product.stock_quantity,
                purchase_price=product.purchase_price,
                note='أول عملية شراء (إضافة المنتج)',
                created_at=product.created_at or datetime.utcnow()
            )
            db.session.add(initial_log)
            db.session.commit()
            history = [initial_log]

        return jsonify({'status': 'success', 'history': [h.to_dict() for h in history]})

    @app.route('/api/products/barcode/<path:barcode>', methods=['GET'])
    def get_product_by_barcode(barcode):
        product = Product.query.filter_by(barcode=barcode).first()
        if product:
            return jsonify({'status': 'success', 'product': product.to_dict()})
        return jsonify({'status': 'error', 'message': 'المنتج غير موجود'}), 404

    # ================= SALES & POS APIs =================
    @app.route('/api/sales', methods=['POST'])
    def create_sale():
        return create_sale_transaction()

    def _filter_sales_and_expenses(args):
        try:
            period, display_start, display_end, utc_start, utc_end, tz_delta, resolved = report_window(args)
        except (ValueError, TypeError, KeyError) as error:
            raise BadRequest(str(error))

        # Filter Sales
        sales_q = Sale.query
        if utc_start and utc_end:
            sales_q = sales_q.filter(Sale.created_at >= utc_start, Sale.created_at < utc_end)

        payment_method = args.get('payment_method')
        if payment_method and payment_method != 'all':
            sales_q = sales_q.filter(Sale.payment_method == payment_method)

        cashier = args.get('cashier')
        if cashier and cashier != 'all':
            sales_q = sales_q.filter(Sale.cashier_name == cashier)

        search = (args.get('search') or '').strip()
        if search:
            sales_q = sales_q.filter(
                db.or_(
                    Sale.cashier_name.ilike(f'%{search}%'),
                    Sale.payment_method.ilike(f'%{search}%'),
                    db.cast(Sale.id, db.String).ilike(f'%{search}%')
                )
            )

        all_sales = sales_q.order_by(Sale.id.desc()).all()

        # Filter Expenses
        exp_q = Expense.query
        if utc_start and utc_end:
            exp_q = exp_q.filter(Expense.created_at >= utc_start, Expense.created_at < utc_end)
        all_expenses = exp_q.order_by(Expense.id.desc()).all()

        return period, display_start, display_end, all_sales, all_expenses, tz_delta, resolved

    @app.route('/api/sales', methods=['GET'])
    def get_sales():
        period, display_start, display_end, all_sales, all_expenses, tz_delta, resolved = _filter_sales_and_expenses(request.args)
        sales_dicts = []
        for s in all_sales:
            d = s.to_dict()
            if s.created_at:
                d['created_at'] = (s.created_at + tz_delta).strftime('%Y-%m-%d %H:%M:%S')
            sales_dicts.append(d)
        return jsonify({'status': 'success', 'sales': sales_dicts, 'count': len(sales_dicts)})


    # ================= TABLES & ACTIVE ORDERS APIs =================
    
    @app.route('/api/tables', methods=['GET'])
    def get_tables():
        # Using Core System
        return jsonify({'status': 'success', 'tables': core.execute('get_tables', {})})

    
    @app.route('/api/tables', methods=['POST'])
    def create_tables():
        data = request.get_json() or {}
        count = data.get('count', 1)
        
        try:
            count = int(count)
        except ValueError:
            return jsonify({'status': 'error', 'message': 'العدد غير صحيح'}), 400

        if count <= 0:
            return jsonify({'status': 'error', 'message': 'العدد يجب أن يكون أكبر من صفر'}), 400

        max_table = db.session.query(db.func.max(Table.table_number)).scalar() or 0
        
        new_tables = []
        for i in range(1, count + 1):
            new_table = Table(table_number=max_table + i)
            db.session.add(new_table)
            new_tables.append(new_table)
            
        db.session.commit()
        
        return jsonify({'status': 'success', 'message': f'تمت إضافة {count} طاولة بنجاح', 'tables': [t.to_dict() for t in new_tables]}), 201

    @app.route('/api/tables/<int:table_id>', methods=['DELETE'])
    def delete_table(table_id):
        table = Table.query.get(table_id)
        if not table:
            return jsonify({'status': 'error', 'message': 'الطاولة غير موجودة'}), 404
            
        if table.is_active:
            return jsonify({'status': 'error', 'message': 'لا يمكن حذف طاولة مشغولة بطلبات حالياً'}), 400
            
        db.session.delete(table)
        db.session.commit()
        return jsonify({'status': 'success', 'message': 'تم حذف الطاولة بنجاح'})

    @app.route('/api/tables/<int:table_id>/order', methods=['GET'])
    def get_table_order(table_id):
        table = Table.query.get(table_id)
        if not table:
            return jsonify({'status': 'error', 'message': 'الطاولة غير موجودة'}), 404
            
        active_order = ActiveOrder.query.filter_by(table_id=table_id).first()
        if active_order:
            return jsonify({'status': 'success', 'has_order': True, 'order': active_order.to_dict()})
        else:
            return jsonify({'status': 'success', 'has_order': False})

    @app.route('/api/tables/<int:table_id>/order', methods=['POST'])
    def save_table_order(table_id):
        return save_table_transaction(table_id)

    # ================= EXPENSES APIs =================
    @app.route('/api/expenses', methods=['GET'])
    def get_expenses():
        expenses = Expense.query.order_by(Expense.id.desc()).all()
        total_expense = sum(e.amount for e in expenses)
        return jsonify({'status': 'success', 'total_amount': round(total_expense, 2), 'expenses': [e.to_dict() for e in expenses]})

    @app.route('/api/expenses', methods=['POST'])
    def create_expense():
        data = request.get_json() or {}
        title = data.get('title', '').strip()
        try:
            amount = number(data.get('amount', 0))
        except ValueError as error:
            return failure(str(error), 400)

        if not title or amount <= 0:
            return jsonify({'status': 'error', 'message': 'العنوان والمبلغ الجاري مطلوبان'}), 400

        expense = Expense(
            title=title,
            amount=amount,
            category=data.get('category', 'عام'),
            notes=data.get('notes', ''),
            created_by=g.current_user.full_name
        )
        db.session.add(expense)
        db.session.commit()

        return jsonify({'status': 'success', 'message': 'تم تسجيل المصروف بنجاح', 'expense': expense.to_dict()}), 201

    @app.route('/api/expenses/<int:expense_id>', methods=['DELETE'])
    def delete_expense(expense_id):
        exp = Expense.query.get(expense_id)
        if not exp:
            return jsonify({'status': 'error', 'message': 'المصروف غير موجود'}), 404
        if exp.source in ['payroll', 'fixed', 'inventory'] or exp.category == 'مشتريات/بضاعة':
            return failure('مصروف مرتبط بسجل مالي؛ لا يمكن حذفه من المصاريف.', 409)
        db.session.delete(exp)
        db.session.commit()
        return jsonify({'status': 'success', 'message': 'تم حذف المصروف بنجاح'})

    @app.put('/api/expenses/<int:expense_id>')
    def update_expense(expense_id):
        expense = db.session.get(Expense, expense_id)
        if not expense: return failure('المصروف غير موجود.', 404)
        if expense.source in ['payroll', 'fixed', 'inventory'] or expense.category == 'مشتريات/بضاعة':
            return failure('السجل مرتبط بعملية مالية ولا يُعدل من هنا.', 409)
        d = request.get_json() or {}
        try:
            amount = number(d.get('amount', expense.amount))
            title = str(d.get('title', expense.title)).strip()
            category = str(d.get('category', expense.category)).strip()
            if amount <= 0 or not title or len(title) > 150 or len(category) > 80:
                raise ValueError('تحقق من العنوان والمبلغ والتصنيف.')
            if category == 'مشتريات/بضاعة': raise ValueError('سجّل توريد البضاعة من صفحة المنتجات.')
            expense.title, expense.amount, expense.category = title, round(amount, 2), category or 'عام'
            expense.notes = str(d.get('notes', expense.notes))[:255]
            db.session.commit()
            return jsonify(expense=expense.to_dict())
        except ValueError as error:
            return failure(str(error), 400)

    # ================= ANALYTICS APIs =================
    @app.route('/api/stats', methods=['GET'])
    def get_stats():
        period, display_start, display_end, all_sales, all_expenses, tz_delta, resolved = _filter_sales_and_expenses(request.args)

        total_sales_count = len(all_sales)
        gross_sales = sum(s.total_selling_amount for s in all_sales)
        total_discount = sum(s.total_discount for s in all_sales)
        total_revenue = sum(s.total_selling_amount - s.total_discount for s in all_sales)
        total_cost = sum(s.total_purchase_cost for s in all_sales)
        gross_profit = sum(s.net_profit for s in all_sales)
        inventory_expenses = [e for e in all_expenses if e.source == 'inventory' or e.category == 'مشتريات/بضاعة']
        operating_expenses = [e for e in all_expenses if e not in inventory_expenses]
        total_supply = sum(e.amount for e in inventory_expenses)
        total_expenses = sum(e.amount for e in operating_expenses)
        expense_categories = {}
        for e in operating_expenses:
            category = e.category or 'عام'
            expense_categories[category] = expense_categories.get(category, 0) + e.amount
        final_net_profit = gross_profit - total_expenses
        avg_order_value = (total_revenue / total_sales_count) if total_sales_count > 0 else 0.0
        profit_margin = ((gross_profit / total_revenue) * 100) if total_revenue > 0 else 0.0

        # Payment methods breakdown
        pm_dict = {}
        for s in all_sales:
            pm = s.payment_method or 'نقداً'
            if pm not in pm_dict:
                pm_dict[pm] = {'amount': 0.0, 'count': 0}
            pm_dict[pm]['amount'] += (s.total_selling_amount - s.total_discount)
            pm_dict[pm]['count'] += 1

        # Products ranking & total items sold
        prod_map = {}
        total_items_sold = 0.0
        for s in all_sales:
            for item in s.items:
                pname = item.product_name
                qty = item.quantity or 0.0
                total_items_sold += qty
                if pname not in prod_map:
                    prod_map[pname] = {
                        'product_name': pname,
                        'quantity': 0.0,
                        'total_revenue': 0.0,
                        'total_profit': 0.0
                    }
                prod_map[pname]['quantity'] += qty
                prod_map[pname]['total_revenue'] += (item.total_price or 0.0)
                prod_map[pname]['total_profit'] += (item.profit or 0.0)

        top_products = sorted(prod_map.values(), key=lambda x: x['quantity'], reverse=True)[:10]
        for p in top_products:
            p['quantity'] = round(p['quantity'], 2)
            p['total_revenue'] = round(p['total_revenue'], 2)
            p['total_profit'] = round(p['total_profit'], 2)

        # Timeline grouping for chart
        timeline_buckets = {}
        if period in ['today', 'yesterday']:
            for h in range(24):
                lbl = f"{h:02d}:00"
                timeline_buckets[lbl] = {'label': lbl, 'revenue': 0.0, 'profit': 0.0, 'orders': 0}
            for s in all_sales:
                if s.created_at:
                    local_t = s.created_at + tz_delta
                    lbl = f"{local_t.hour:02d}:00"
                    if lbl in timeline_buckets:
                        timeline_buckets[lbl]['revenue'] += (s.total_selling_amount - s.total_discount)
                        timeline_buckets[lbl]['profit'] += s.net_profit
                        timeline_buckets[lbl]['orders'] += 1
        elif period in ['week', 'month', 'custom', 'hours', 'custom_time']:
            for s in all_sales:
                if s.created_at:
                    local_t = s.created_at + tz_delta
                    lbl = local_t.strftime('%Y-%m-%d %H:00' if period in ['hours', 'custom_time'] and (datetime.fromisoformat(resolved['end_at'].replace('Z', '+00:00')) - datetime.fromisoformat(resolved['start_at'].replace('Z', '+00:00'))).total_seconds() <= 172800 else '%Y-%m-%d')
                    if lbl not in timeline_buckets:
                        timeline_buckets[lbl] = {'label': lbl, 'revenue': 0.0, 'profit': 0.0, 'orders': 0}
                    timeline_buckets[lbl]['revenue'] += (s.total_selling_amount - s.total_discount)
                    timeline_buckets[lbl]['profit'] += s.net_profit
                    timeline_buckets[lbl]['orders'] += 1
        else: # year or all
            for s in all_sales:
                if s.created_at:
                    local_t = s.created_at + tz_delta
                    lbl = local_t.strftime('%Y-%m')
                    if lbl not in timeline_buckets:
                        timeline_buckets[lbl] = {'label': lbl, 'revenue': 0.0, 'profit': 0.0, 'orders': 0}
                    timeline_buckets[lbl]['revenue'] += (s.total_selling_amount - s.total_discount)
                    timeline_buckets[lbl]['profit'] += s.net_profit
                    timeline_buckets[lbl]['orders'] += 1

        timeline = list(timeline_buckets.values())
        if period not in ['today', 'yesterday']:
            timeline.sort(key=lambda x: x['label'])
        for pt in timeline:
            pt['revenue'] = round(pt['revenue'], 2)
            pt['profit'] = round(pt['profit'], 2)

        # Sales with local formatted date
        sales_dicts = []
        for s in all_sales:
            d = s.to_dict()
            if s.created_at:
                d['created_at'] = (s.created_at + tz_delta).strftime('%Y-%m-%d %H:%M:%S')
            d['items_count'] = len(s.items)
            sales_dicts.append(d)

        total_products_count = Product.query.count()

        return jsonify({
            'status': 'success',
            'period': period,
            'resolved_filter': resolved,
            'start_date': display_start,
            'end_date': display_end,
            'stats': {
                'total_sales_count': total_sales_count,
                'total_revenue': round(total_revenue, 2),
                'gross_sales': round(gross_sales, 2),
                'total_cost': round(total_cost, 2),
                'total_discount': round(total_discount, 2),
                'gross_profit': round(gross_profit, 2),
                'total_expenses': round(total_expenses, 2),
                'total_supply': round(total_supply, 2),
                'total_outflows': round(total_supply + total_expenses, 2),
                'sales_less_outflows': round(total_revenue - total_supply - total_expenses, 2),
                'profit': round(max(final_net_profit, 0), 2),
                'loss': round(max(-final_net_profit, 0), 2),
                'salary_expenses': round(expense_categories.get('رواتب', 0), 2),
                'rent_expenses': round(expense_categories.get('إيجار', 0) + expense_categories.get('إيجارات', 0), 2),
                'subscription_expenses': round(expense_categories.get('اشتراكات', 0), 2),
                'fixed_expenses': round(sum(e.amount for e in operating_expenses if e.source == 'fixed'), 2),
                'final_net_profit': round(final_net_profit, 2),
                'average_order_value': round(avg_order_value, 2),
                'profit_margin_pct': round(profit_margin, 1),
                'total_items_sold': round(total_items_sold, 2),
                'total_products': total_products_count
            },
            'payment_methods': {k: {'amount': round(v['amount'], 2), 'count': v['count']} for k, v in pm_dict.items()},
            'expenses': [dict(e.to_dict(), created_at=(e.created_at + tz_delta).strftime('%Y-%m-%d %H:%M:%S')) for e in all_expenses],
            'expense_categories': {k: round(v, 2) for k, v in expense_categories.items()},
            'legacy_inventory_expenses': sum(1 for e in inventory_expenses if e.source != 'inventory'),
            'top_products': top_products,
            'timeline': timeline,
            'sales': sales_dicts
        })

    # ================= DB SWITCHER API =================
    @app.route('/api/switch-db', methods=['POST'])
    def switch_db():
        data = request.get_json() or {}
        new_type = data.get('db_type', '').lower()
        if new_type not in ['sqlite', 'mysql']:
            return jsonify({'status': 'error', 'message': 'Invalid db_type'}), 400

        env_file = os.path.join(os.path.dirname(__file__), '.env')
        lines = []
        if os.path.exists(env_file):
            with open(env_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()

        new_lines = []
        found = False
        for line in lines:
            if line.startswith('DATABASE_TYPE='):
                new_lines.append(f'DATABASE_TYPE={new_type}\n')
                found = True
            else:
                new_lines.append(line)
        if not found:
            new_lines.append(f'DATABASE_TYPE={new_type}\n')

        with open(env_file, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)

        return jsonify({'status': 'success', 'message': f'تم حفظ اختيار {new_type}. يلزم إعادة تشغيل السيرفر لتطبيقه؛ البيانات لا تُنقل تلقائياً', 'db_type': new_type})


    @app.route('/api/action/<action_name>', methods=['POST'])
    def api_core_action(action_name):
        try:
            data = request.json or {}
            result = core.execute(action_name, data)
            return jsonify({'status': 'success', 'data': result})
        except Exception as e:
            return jsonify({'status': 'error', 'message': str(e)}), 400

    install_exports(app, get_stats)
    return app

if __name__ == '__main__':
    app = create_app()
    app.run(host='0.0.0.0', port=5000, debug=True)
