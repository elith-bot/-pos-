import re

app_file = r"c:\Users\Mac-x77\Desktop\كاشير\backend\app.py"
with open(app_file, "r", encoding="utf-8") as f:
    text = f.read()

# Remove the badly inserted dynamic routes
bad_route = """@app.route('/api/action/<action_name>', methods=['POST'])
def api_core_action(action_name):
    try:
        data = request.json or {}
        result = core.execute(action_name, data)
        return jsonify({'status': 'success', 'data': result})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 400

"""

text = text.replace(bad_route, "")
text = text.replace(bad_route.strip(), "") # Just in case

# Fix the get_tables indentation
text = text.replace("@app.route('/api/tables', methods=['GET'])\n    def get_tables():", "    @app.route('/api/tables', methods=['GET'])\n    def get_tables():")
text = text.replace("@app.route('/api/tables', methods=['POST'])\n    def create_tables():", "    @app.route('/api/tables', methods=['POST'])\n    def create_tables():")

# Replace get_tables body properly
search_get_tables = """    @app.route('/api/tables', methods=['GET'])
    def get_tables():
        tables = Table.query.order_by(Table.table_number.asc()).all()
        return jsonify({'status': 'success', 'tables': [t.to_dict() for t in tables]})"""

replace_get_tables = """    @app.route('/api/tables', methods=['GET'])
    def get_tables():
        # Using Core System
        return jsonify({'status': 'success', 'tables': core.execute('get_tables', {})})"""

if search_get_tables in text:
    text = text.replace(search_get_tables, replace_get_tables)
else:
    # Maybe it was already replaced but with bad indentation?
    pass

# Insert the dynamic route at the end of create_app, before `return app`
dynamic_route_clean = """
    @app.route('/api/action/<action_name>', methods=['POST'])
    def api_core_action(action_name):
        try:
            data = request.json or {}
            result = core.execute(action_name, data)
            return jsonify({'status': 'success', 'data': result})
        except Exception as e:
            return jsonify({'status': 'error', 'message': str(e)}), 400
"""
# find the last route before `return app`
idx = text.rfind("    return app")
if idx != -1 and "api_core_action" not in text:
    text = text[:idx] + dynamic_route_clean + "\n" + text[idx:]

with open(app_file, "w", encoding="utf-8") as f:
    f.write(text)

print("app.py fixed successfully")
