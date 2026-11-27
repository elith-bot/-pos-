"""Unit tests for Peer Gateway and symmetric full-stack node topology."""
import unittest
import json
from unittest.mock import patch, MagicMock
from app import create_app


class PeerGatewayTestCase(unittest.TestCase):
    def setUp(self):
        self.group_id = 'group_symmetric_999'

    def test_standalone_node_handles_requests_locally(self):
        """Standalone node serves requests locally without peer forwarding."""
        app = create_app({
            'TESTING': True,
            'SQLALCHEMY_DATABASE_URI': 'sqlite:///:memory:',
            'LICENSE_REQUIRED': False,
            'TOPOLOGY': {'mode': 'standalone'}
        })
        client = app.test_client()
        res = client.get('/api/license')
        self.assertEqual(res.status_code, 200)

    @patch('urllib.request.urlopen')
    def test_terminal_node_forwards_shared_requests_to_server(self, mock_urlopen):
        """Terminal node forwards shared business API requests to main server with headers."""
        mock_resp = MagicMock()
        mock_resp.status = 200
        mock_resp.read.return_value = b'{"status":"success","items":[]}'
        mock_resp.getheaders.return_value = [('Content-Type', 'application/json')]
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        app = create_app({
            'TESTING': True,
            'SQLALCHEMY_DATABASE_URI': 'sqlite:///:memory:',
            'LICENSE_REQUIRED': False,
            'EDITION_ID': 'ed_terminal_01',
            'TOPOLOGY': {
                'mode': 'terminal',
                'group_id': self.group_id,
                'server_address': 'http://192.168.1.100:5000',
                'terminal_name': 'كاشير الصالة 1'
            }
        })
        client = app.test_client()

        res = client.get('/api/products')
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'items', res.data)

        # Verify outgoing request injected group headers
        args, _ = mock_urlopen.call_args
        req = args[0]
        self.assertEqual(req.headers.get('X-pos-group-id'), self.group_id)
        self.assertEqual(req.full_url, 'http://192.168.1.100:5000/api/products')

    @patch('urllib.request.urlopen')
    def test_terminal_node_handles_offline_server_gracefully(self, mock_urlopen):
        """When main server is unreachable, terminal returns informative 503 error."""
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError('Connection refused')

        app = create_app({
            'TESTING': True,
            'SQLALCHEMY_DATABASE_URI': 'sqlite:///:memory:',
            'LICENSE_REQUIRED': False,
            'TOPOLOGY': {
                'mode': 'terminal',
                'group_id': self.group_id,
                'server_address': 'http://192.168.1.100:5000',
                'terminal_name': 'كاشير الصالة 1'
            }
        })
        client = app.test_client()

        res = client.get('/api/sales')
        self.assertEqual(res.status_code, 503)
        data = res.get_json()
        self.assertEqual(data.get('code'), 'server_offline')
        self.assertIn('السيرفر الرئيسي غير متصل', data.get('message', ''))


if __name__ == '__main__':
    unittest.main()
