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
    installation = Path(installation).resolve()
    if installation.parent.name == 'POS Cashier':
        legacy = installation.parent.parent / installation.name
        manifest = legacy/'_internal'/'deployment.pos'
        if manifest.is_file() and (legacy/'Data'/'cashier.db').is_file():
            from license_protocol import verify
            from trusted_license import PUBLIC_KEY
            payload = verify(manifest.read_text(encoding='utf-8'), PUBLIC_KEY, 'deployment')
            if payload['edition_id'] == edition_id:
                old = legacy/'Data'

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
