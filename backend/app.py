import os
import random
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy.exc import OperationalError
from config import Config

from models import db, User, OTPCode, Product, Sale, SaleItem, Expense, RestockHistory

def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    CORS(app)
    db.init_app(app)

    with app.app_context():
        try:
            db.create_all()
            
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

            # Seed initial Developer account if users table is empty
            if User.query.count() == 0:
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

                db.session.commit()
                print("Seeded default developer user and sample products.")
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

        if not username or not password or not full_name:
            return jsonify({'status': 'error', 'message': 'جميع الحقول مطلوبة (اسم المستخدم، كلمة المرور، الاسم الكامل)'}), 400

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

        user.role = new_role
        db.session.commit()
        return jsonify({'status': 'success', 'message': f'تم تغيير دور المستخدم إلى {new_role}', 'user': user.to_dict()})

    @app.route('/api/users/<int:user_id>/toggle-active', methods=['PUT'])
    def toggle_user_active(user_id):
        user = User.query.get(user_id)
        if not user:
            return jsonify({'status': 'error', 'message': 'المستخدم غير موجود'}), 404

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

        if product.stock_quantity > 0:
            restock_log = RestockHistory(
                product_id=product.id,
                quantity=product.stock_quantity,
                purchase_price=product.purchase_price
            )
            db.session.add(restock_log)
            
            expense = Expense(
                title=f'رصيد بضاعة أولي: {product.name}',
                amount=product.stock_quantity * product.purchase_price,
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
        added_qty = float(data.get('added_quantity', 0))
        new_purchase_price = data.get('purchase_price')

        if added_qty <= 0:
            return jsonify({'status': 'error', 'message': 'يجب إدخال كمية موجبة للتوريد'}), 400

        product.stock_quantity += added_qty
        if new_purchase_price is not None:
            product.purchase_price = float(new_purchase_price)

        restock_log = RestockHistory(
            product_id=product.id,
            quantity=added_qty,
            purchase_price=product.purchase_price
        )
        db.session.add(restock_log)
        
        expense = Expense(
            title=f'توريد بضاعة: {product.name}',
            amount=added_qty * product.purchase_price,
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
        history = RestockHistory.query.filter_by(product_id=product_id).order_by(RestockHistory.id.desc()).all()
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
        data = request.get_json() or {}
        cart_items = data.get('items', [])
        cashier_name = data.get('cashier_name', 'كاشير')
        cashier_id = data.get('cashier_id')
        payment_method = data.get('payment_method', 'نقداً')
        global_discount = float(data.get('global_discount', 0.0))

        if not cart_items:
            return jsonify({'status': 'error', 'message': 'السلة فارغة'}), 400

        total_purchase_cost = 0.0
        total_selling_amount = 0.0
        total_discount = 0.0
        net_profit = 0.0

        sale_items_to_add = []

        for item_data in cart_items:
            product_id = item_data.get('product_id')
            qty = float(item_data.get('quantity', 1))
            unit_purchase = float(item_data.get('unit_purchase_price', 0))
            unit_selling = float(item_data.get('unit_selling_price', 0))
            discount = float(item_data.get('discount', 0)) # Can be negative

            item_total = (unit_selling - discount) * qty
            item_cost = unit_purchase * qty
            item_profit = item_total - item_cost

            total_purchase_cost += item_cost
            total_selling_amount += unit_selling * qty
            total_discount += discount * qty
            net_profit += item_profit

            # Update product stock
            if product_id:
                product = Product.query.get(product_id)
                if product:
                    product.stock_quantity = max(0, product.stock_quantity - qty)

            sale_items_to_add.append(SaleItem(
                product_id=product_id,
                product_name=item_data.get('product_name', 'منتج'),
                quantity=qty,
                unit_purchase_price=unit_purchase,
                unit_selling_price=unit_selling,
                discount=discount,
                total_price=item_total,
                profit=item_profit
            ))

        total_discount += global_discount
        net_profit -= global_discount

        sale = Sale(
            cashier_id=cashier_id,
            cashier_name=cashier_name,
            total_purchase_cost=total_purchase_cost,
            total_selling_amount=total_selling_amount,
            total_discount=total_discount,
            net_profit=net_profit,
            payment_method=payment_method
        )
        db.session.add(sale)
        db.session.flush()

        for s_item in sale_items_to_add:
            s_item.sale_id = sale.id
            db.session.add(s_item)

        db.session.commit()

        return jsonify({'status': 'success', 'message': 'تم إكمال عملية البيع بنجاح', 'sale': sale.to_dict()}), 201

    @app.route('/api/sales', methods=['GET'])
    def get_sales():
        sales = Sale.query.order_by(Sale.id.desc()).limit(100).all()
        return jsonify({'status': 'success', 'sales': [s.to_dict() for s in sales]})

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
        amount = float(data.get('amount', 0))

        if not title or amount <= 0:
            return jsonify({'status': 'error', 'message': 'العنوان والمبلغ الجاري مطلوبان'}), 400

        expense = Expense(
            title=title,
            amount=amount,
            category=data.get('category', 'عام'),
            notes=data.get('notes', ''),
            created_by=data.get('created_by', 'المدير')
        )
        db.session.add(expense)
        db.session.commit()

        return jsonify({'status': 'success', 'message': 'تم تسجيل المصروف بنجاح', 'expense': expense.to_dict()}), 201

    @app.route('/api/expenses/<int:expense_id>', methods=['DELETE'])
    def delete_expense(expense_id):
        exp = Expense.query.get(expense_id)
        if not exp:
            return jsonify({'status': 'error', 'message': 'المصروف غير موجود'}), 404
        db.session.delete(exp)
        db.session.commit()
        return jsonify({'status': 'success', 'message': 'تم حذف المصروف بنجاح'})

    # ================= ANALYTICS APIs =================
    @app.route('/api/stats', methods=['GET'])
    def get_stats():
        total_sales_count = Sale.query.count()
        total_revenue = db.session.query(db.func.sum(Sale.total_selling_amount - Sale.total_discount)).scalar() or 0.0
        total_cost = db.session.query(db.func.sum(Sale.total_purchase_cost)).scalar() or 0.0
        gross_profit = db.session.query(db.func.sum(Sale.net_profit)).scalar() or 0.0
        total_expenses = db.session.query(db.func.sum(Expense.amount)).scalar() or 0.0
        final_net_profit = gross_profit - total_expenses
        total_products = Product.query.count()

        return jsonify({
            'status': 'success',
            'stats': {
                'total_sales_count': total_sales_count,
                'total_revenue': round(total_revenue, 2),
                'total_cost': round(total_cost, 2),
                'gross_profit': round(gross_profit, 2),
                'total_expenses': round(total_expenses, 2),
                'final_net_profit': round(final_net_profit, 2),
                'total_products': total_products
            }
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

        return jsonify({'status': 'success', 'message': f'تم تغيير نوع قاعدة البيانات إلى {new_type}', 'db_type': new_type})

    return app

if __name__ == '__main__':
    app = create_app()
    app.run(host='0.0.0.0', port=5000, debug=True)
