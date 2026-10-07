import os
import re

app_file = r"c:\Users\Mac-x77\Desktop\كاشير\backend\app.py"
with open(app_file, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add imports at the top
if "from core_system import core" not in content:
    content = content.replace(
        "from models import db,", 
        "from models import db,\nfrom core_system import core\nimport actions\n"
    )

# 2. Add dynamic action route
dynamic_route = """
@app.route('/api/action/<action_name>', methods=['POST'])
def api_core_action(action_name):
    try:
        data = request.json or {}
        result = core.execute(action_name, data)
        return jsonify({'status': 'success', 'data': result})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 400
"""
if "@app.route('/api/action/<action_name>'" not in content:
    # Insert it before get_tables
    content = content.replace(
        "@app.route('/api/tables'", 
        dynamic_route + "\n@app.route('/api/tables'"
    )

# 3. Replace get_tables body
search_get_tables = """@app.route('/api/tables', methods=['GET'])
def get_tables():
    tables = Table.query.all()
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
            'name': t.name,
            'is_active': t.is_active,
            'total_price': total_price
        })
    return jsonify(result)"""

replace_get_tables = """@app.route('/api/tables', methods=['GET'])
def get_tables():
    # Now using the centralized Core System!
    return jsonify(core.execute("get_tables", {}))"""

content = content.replace(search_get_tables, replace_get_tables)

with open(app_file, "w", encoding="utf-8") as f:
    f.write(content)

print("app.py updated successfully")
