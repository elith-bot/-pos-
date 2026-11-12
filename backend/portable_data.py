"""Keep customer data beside the executable; migrate older per-user data safely."""
import os
import sqlite3
import shutil
from contextlib import closing
from pathlib import Path

def prepare_data(installation, edition_id):
    data = Path(installation) / 'Data'
    data.mkdir(parents=True, exist_ok=True)
    old = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'POS Cashier' / edition_id
    target = data / 'cashier.db'
    if not target.exists() and (old / 'cashier.db').is_file():
        temporary = data / 'cashier-migration.tmp'
        with closing(sqlite3.connect((old / 'cashier.db').resolve().as_uri() + '?mode=ro', uri=True)) as source:
            with closing(sqlite3.connect(temporary)) as backup:
                source.backup(backup)
                if backup.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                    raise RuntimeError('تعذر التحقق من سلامة قاعدة البيانات القديمة.')
        os.replace(temporary, target)
    if not (data / 'license.lic').exists() and (old / 'license.lic').is_file():
        shutil.copy2(old / 'license.lic', data / 'license.lic')
    return data
