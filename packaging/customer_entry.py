"""Start the local backend, network server or terminal relay, and launch native Flutter window."""
import ctypes
import json
import os
import subprocess
import sys
import threading
import traceback
from pathlib import Path


def main():
    server = None
    try:
        from waitress import create_server
        from trusted_license import EDITION_ID, APP_NAME, PUBLIC_KEY
        from portable_data import prepare_data
        from license_protocol import verify

        bundle = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parent))
        native = bundle / 'native' / (APP_NAME + '.exe')
        if not native.is_file():
            raise RuntimeError('ملفات واجهة ويندوز ناقصة. أعد التنصيب.')
        data = prepare_data(Path(sys.executable).resolve().parent, EDITION_ID)

        # Load signed deployment topology
        deployment = verify((bundle / 'deployment.pos').read_text(encoding='utf-8'), PUBLIC_KEY, 'deployment')
        topology = deployment.get('topology', {})
        mode = topology.get('mode', 'standalone')

        if mode == 'terminal':
            from terminal_relay import create_terminal_app
            app = create_terminal_app(str(bundle), str(data), topology, EDITION_ID)
            server = create_server(app, host='127.0.0.1', port=5000, threads=6)
        else:
            from app import create_app
            app = create_app(dict(
                LICENSE_REQUIRED=True,
                LICENSE_BUNDLE_DIR=str(bundle),
                LICENSE_DATA_DIR=str(data),
                DATABASE_TYPE='sqlite',
                SQLALCHEMY_DATABASE_URI='sqlite:///' + (data / 'cashier.db').as_posix(),
                REPORT_FONT_PATH=str(bundle / 'fonts/NotoSansArabic.ttf'),
                TOPOLOGY=topology
            ))
            if not app.extensions.get('pos_license'):
                raise RuntimeError('ملفات هذه النسخة غير صحيحة. أعد التنصيب من النسخة الأصلية.')
            bind_host = '0.0.0.0' if mode == 'server' else '127.0.0.1'
            server = create_server(app, host=bind_host, port=5000, threads=8)

        threading.Thread(target=server.run, daemon=True).start()
        subprocess.run([str(native)], cwd=native.parent, check=True)
        return 0
    except Exception as error:
        log = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'POS Cashier' / 'startup-error.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(traceback.format_exc(), encoding='utf-8')
        ctypes.windll.user32.MessageBoxW(None, str(error) + '\nسجل الخطأ: ' + str(log), 'تعذر تشغيل الكاشير', 0x10)
        return 1
    finally:
        if server is not None:
            server.close()


if __name__ == '__main__':
    sys.exit(main())
