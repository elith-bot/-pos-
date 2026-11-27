"""Peer-to-peer network forwarding gateway.
Enables full-stack cashier nodes to synchronize operations with the primary shop server
while operating as independent full-featured cashier instances.
"""
import urllib.request
import urllib.error
import urllib.parse
from flask import request, Response, jsonify


SHARED_API_PREFIXES = (
    '/api/sales',
    '/api/products',
    '/api/tables',
    '/api/expenses',
    '/api/stats',
    '/api/users',
    '/api/auth/login',
    '/api/hr',
    '/api/roles',
    '/api/exports',
    '/api/settings',
    '/api/support',
)


def install_peer_gateway(app):
    topology = app.config.get('TOPOLOGY') or {}
    mode = topology.get('mode', 'standalone')
    server_address = (topology.get('server_address') or '').rstrip('/')
    group_id = topology.get('group_id', '')
    terminal_name = topology.get('terminal_name', 'كاشير فرعي')
    edition_id = app.config.get('EDITION_ID', '')

    if mode != 'terminal' or not server_address:
        # Standalone or Server nodes handle all requests locally
        return

    @app.before_request
    def peer_forwarder():
        path = request.path
        if request.method == 'OPTIONS':
            return None

        # Local licensing and health check are always resolved locally on this device
        if path in {'/api/license', '/api/license/activate', '/health'}:
            return None

        # Check if the requested path belongs to shared business operations
        if any(path == prefix or path.startswith(prefix + '/') for prefix in SHARED_API_PREFIXES):
            # Forward to primary shop server
            target_url = f"{server_address}{path}"
            if request.query_string:
                target_url += f"?{request.query_string.decode('utf-8')}"

            req_headers = {}
            for key, value in request.headers.items():
                if key.lower() not in {'host', 'content-length'}:
                    req_headers[key] = value

            req_headers['X-POS-Group-ID'] = group_id
            req_headers['X-POS-Terminal-Name'] = urllib.parse.quote(terminal_name.encode('utf-8'))
            req_headers['X-POS-Terminal-Edition'] = edition_id

            body = request.get_data() if request.method in {'POST', 'PUT', 'PATCH', 'DELETE'} else None
            req = urllib.request.Request(target_url, data=body, headers=req_headers, method=request.method)

            try:
                with urllib.request.urlopen(req, timeout=8) as response:
                    resp_headers = [(k, v) for k, v in response.getheaders() if k.lower() not in {'transfer-encoding', 'content-length', 'content-encoding'}]
                    return Response(response.read(), status=response.status, headers=resp_headers)
            except urllib.error.HTTPError as error:
                err_headers = [(k, v) for k, v in error.headers.items() if k.lower() not in {'transfer-encoding', 'content-length', 'content-encoding'}]
                return Response(error.read(), status=error.code, headers=err_headers)
            except urllib.error.URLError:
                msg = f"تعذر الاتصال بسيرفر المحل الرئيسي ({server_address})، السيرفر الرئيسي غير متصل حالياً. شغّل الكاشير الرئيسي لاستمرار البيع المشترك وتفادي تضارب المخزون."
                return jsonify(status='error', code='server_offline', message=msg), 503

        return None
