"""Build only the vendor desktop tool, with no private keys or customer files."""
import os
from pathlib import Path
import subprocess
import shutil
import sys

root = Path(__file__).resolve().parents[1]
output_root = root / 'dist' / 'updated-admin'
env = dict(os.environ)
env['PYTHONPATH'] = os.pathsep.join([str(root / 'release-build' / 'tooling'), str(root / 'backend'), str(root / 'admin_console')])
subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--onedir', '--windowed',
    '--name', 'POSAdmin', '--distpath', str(output_root), '--workpath', str(root / 'release-build' / 'admin'),
    '--specpath', str(root / 'release-build'), '--paths', str(root / 'backend'), '--paths', str(root / 'admin_console'),
    str(root / 'admin_console' / 'app.py')], check=True, env=env, cwd=root)

# Build kit belongs only to the vendor package. Allowlist source; never copy .env,
# business databases, exports, signing keys or the administrator's customer records.
kit = output_root / 'POSAdmin' / 'build-kit'
for folder in ['backend', 'packaging']:
    for source in (root / folder).glob('*.py'):
        if source.name.startswith('test_'): continue
        target = kit / folder / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
for relative in ['frontend/build/windows/x64/runner/Release', 'frontend/assets/fonts', 'release-build/tooling']:
    shutil.copytree(root / relative, kit / relative, dirs_exist_ok=True)
shutil.copy2(root / 'backend' / 'requirements.txt', kit / 'backend' / 'requirements.txt')
