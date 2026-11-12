"""Windows customer launcher. Serves the bundled Flutter web UI entirely locally."""
import os
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox
from flask import send_from_directory
from waitress import create_server
from app import create_app


def main():
    bundle = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parent))
    # Program data is separate from installer files so upgrades preserve sales and licenses.
    from trusted_license import EDITION_ID, APP_NAME
    from portable_data import prepare_data
    data = prepare_data(Path(sys.executable).resolve().parent, EDITION_ID)
    data.mkdir(parents=True, exist_ok=True)
    window = tk.Tk()
    window.title('الكاشير'); window.geometry('500x240')
    label = ttk.Label(window, text='جارٍ تشغيل الكاشير…', anchor='center', font=('Segoe UI', 16)); label.pack(fill='x', padx=20, pady=30)
    window.update()
    try:
        app = create_app(dict(
            LICENSE_REQUIRED=True, LICENSE_BUNDLE_DIR=str(bundle), LICENSE_DATA_DIR=str(data),
            DATABASE_TYPE='sqlite', SQLALCHEMY_DATABASE_URI='sqlite:///' + (data / 'cashier.db').as_posix(),
            REPORT_FONT_PATH=str(bundle / 'fonts' / 'NotoSansArabic.ttf'),
        ))
        if not app.extensions.get('pos_license'):
            raise RuntimeError('ملفات هذه النسخة غير صحيحة. أعد تنصيب النسخة الأصلية.')

        @app.get('/')
        def index(): return send_from_directory(bundle / 'web', 'index.html')

        @app.get('/<path:filename>')
        def assets(filename): return send_from_directory(bundle / 'web', filename)

        server = create_server(app, host='127.0.0.1', port=5000, threads=4)
        threading.Thread(target=server.run, daemon=True).start()
        import subprocess
        native = bundle / 'native' / (APP_NAME + '.exe')
        if not native.is_file(): raise RuntimeError('ملفات واجهة ويندوز ناقصة. أعد التنصيب.')
        window.withdraw()
        process = subprocess.Popen([str(native)], cwd=native.parent)
        def poll():
            if process.poll() is not None:
                server.close(); window.destroy()
            else: window.after(500, poll)
        poll()
        window.mainloop()
    except Exception as error:
        messagebox.showerror('تعذر تشغيل الكاشير', f'{error}\nإذا كانت نسخة أخرى تعمل فأغلقها ثم حاول مجدداً.', parent=window)
        window.destroy()
        raise


if __name__ == '__main__': main()
