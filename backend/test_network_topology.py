"""Unit tests for LAN network topology and terminal proxy relay."""
import unittest
import json
from unittest.mock import patch, MagicMock
from app import create_app
from models import db, User
from werkzeug.security import generate_password_hash
from terminal_relay import create_terminal_app


class NetworkTopologyTestCase(unittest.TestCase):
    def setUp(self):
        self.group_id = 'test_group_lan_123'
        self.server_app = create_app({
            'TESTING': True,
            'SQLALCHEMY_DATABASE_URI': 'sqlite:///:memory:',
            'LICENSE_REQUIRED': False,
            'TOPOLOGY': {
                'mode': 'server',
                'group_id': self.group_id,
                'terminal_name': 'الكاشير الرئيسي'
            }
        })
        self.client = self.server_app.test_client()

    def test_local_request_allowed_on_server(self):
        """Localhost requests pass through without group_id header."""
        res = self.client.get('/api/license', environ_base={'REMOTE_ADDR': '127.0.0.1'})
        self.assertEqual(res.status_code, 200)

    def test_lan_request_with_valid_group_allowed(self):
        """LAN requests carrying valid matching X-POS-Group-ID pass through."""
        res = self.client.get(
            '/api/license',
            environ_base={'REMOTE_ADDR': '192.168.1.50'},
            headers={'X-POS-Group-ID': self.group_id}
        )
        self.assertEqual(res.status_code, 200)

    def test_lan_request_with_invalid_group_blocked(self):
        """LAN requests with mismatched group_id are blocked with 403."""
        res = self.client.get(
            '/api/license',
            environ_base={'REMOTE_ADDR': '192.168.1.50'},
            headers={'X-POS-Group-ID': 'intruder_group_999'}
        )
        self.assertEqual(res.status_code, 403)
        data = res.get_json()
        self.assertEqual(data.get('code'), 'unauthorized_terminal')

    def test_lan_request_without_group_blocked(self):
        """LAN requests without group_id header are blocked with 403."""
        res = self.client.get(
            '/api/license',
            environ_base={'REMOTE_ADDR': '192.168.1.50'}
        )
        self.assertEqual(res.status_code, 403)

    @patch('terminal_relay.LicenseManager')
    @patch('urllib.request.urlopen')
    def test_terminal_relay_proxy_forwarding(self, mock_urlopen, mock_lic):
        """Terminal relay proxies requests and injects topology headers."""
        mock_mgr = MagicMock()
        mock_mgr.status.return_value = {'active': True}
        mock_lic.return_value = mock_mgr

        # Mock target server response
        mock_resp = MagicMock()
        mock_resp.status = 200
        mock_resp.read.return_value = b'{"status":"success","data":"items"}'
        mock_resp.getheaders.return_value = [('Content-Type', 'application/json')]
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        topology = {
            'mode': 'terminal',
            'group_id': self.group_id,
            'server_address': 'http://192.168.1.10:5000',
            'terminal_name': 'كاشير الصالة'
        }

        relay_app = create_terminal_app('/fake/bundle', '/fake/data', topology, 'fake_edition_id')
        relay_client = relay_app.test_client()

        res = relay_client.get('/api/products')
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'items', res.data)

        # Verify outgoing request injected group headers
        args, kwargs = mock_urlopen.call_args
        req = args[0]
        self.assertEqual(req.headers.get('X-pos-group-id'), self.group_id)
        self.assertEqual(req.full_url, 'http://192.168.1.10:5000/api/products')


if __name__ == '__main__':
    unittest.main()
