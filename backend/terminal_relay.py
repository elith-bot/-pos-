"""Lightweight LAN relay for terminal mode. Proxies API requests to the main shop server while enforcing local terminal licensing."""
import json
import urllib.request
import urllib.error
from urllib.parse import urlparse
from flask import Flask, request, Response, jsonify
from flask_cors import CORS
from licensing import LicenseManager
from hardware_identity import hardware_fingerprint


def create_terminal_app(bundle_path, data_dir, topology, edition_id):
    app = Flask('terminal_relay')
    CORS(app)

    server_address = (topology.get('server_address') or '').rstrip('/')
    if not server_address:
        server_address = 'http://127.0.0.1:5000'
    group_id = topology.get('group_id', '')
    terminal_name = topology.get('terminal_name', 'كاشير فرعي')

    license_mgr = LicenseManager(bundle_path, data_dir, hardware_fingerprint)
    app.extensions['pos_license'] = license_mgr

    @app.get('/api/license')
    def terminal_license_status():
        status = license_mgr.status()
        status['topology'] = topology
        return jsonify(status)

    @app.post('/api/license/activate')
    def terminal_activate():
        data = request.get_json(silent=True) or {}
        token = data.get('token', '')
        try:
            license_mgr.activate(token)
            return jsonify(license_mgr.status())
        except Exception as error:
            return jsonify(message=str(error)), 400

    @app.route('/', defaults={'path': ''}, methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'])
    @app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'])
    def proxy(path):
        if request.method == 'OPTIONS':
            return Response(status=200)

        # Ensure local terminal is activated before forwarding business API calls
        if path.startswith('api/') and path not in {'api/license', 'api/license/activate'}:
            status = license_mgr.status()
            if not status.get('active'):
                return jsonify(status='error', code='license_required', message=status.get('message', 'النسخة الفرعية تحتاج تفعيل')), 423

        target_url = f"{server_address}/{path}"
        if request.query_string:
            target_url += f"?{request.query_string.decode('utf-8')}"

        req_headers = {}
        for key, value in request.headers.items():
            if key.lower() not in {'host', 'content-length'}:
                req_headers[key] = value

        # Inject LAN topology headers
        req_headers['X-POS-Group-ID'] = group_id
        req_headers['X-POS-Terminal-Name'] = urllib.parse.quote(terminal_name.encode('utf-8'))
        req_headers['X-POS-Terminal-Edition'] = edition_id

        body = request.get_data() if request.method in {'POST', 'PUT', 'PATCH'} else None

        req = urllib.request.Request(target_url, data=body, headers=req_headers, method=request.method)

        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                resp_headers = [(k, v) for k, v in response.getheaders() if k.lower() not in {'transfer-encoding', 'content-length', 'content-encoding'}]
                return Response(response.read(), status=response.status, headers=resp_headers)
        except urllib.error.HTTPError as error:
            err_headers = [(k, v) for k, v in error.headers.items() if k.lower() not in {'transfer-encoding', 'content-length', 'content-encoding'}]
            return Response(error.read(), status=error.code, headers=err_headers)
        except urllib.error.URLError as error:
            msg = f"تعذر الاتصال بسيرفر المحل الرئيسي ({server_address}). تأكد من تشغيل السيرفر الرئيسي واتصال الأجهزة بنفس الشبكة المحلية."
            return jsonify(status='error', code='main_server_unreachable', message=msg), 503

    return app
