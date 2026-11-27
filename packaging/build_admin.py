"""Build only the vendor desktop tool, with no private keys or customer files."""
import os
import argparse
import json
from pathlib import Path
import subprocess
import shutil
import sys

root = Path(__file__).resolve().parents[1]
release = json.loads((root / 'VERSION.json').read_text(encoding='utf-8'))
release_name = f"moon-v{release['version']}-step-{release['step']:03d}-{release['slug']}"
executable_name = f"moon-admin-v{release['version']}-step-{release['step']:03d}"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-root', type=Path, default=root / 'dist' / release_name)
parser.add_argument('--name', default=executable_name,
                    help='Name of the onedir application folder and executable.')
args = parser.parse_args()
output_root = args.output_root.resolve()
app_name = args.name
if not app_name or Path(app_name).name != app_name:
    raise ValueError('اسم مجلد الأدمن غير صالح.')

# A normal refresh must not discard customer exports embedded in the active
# vendor folder.  Stage them outside the PyInstaller target first, then restore
# them once the fresh build kit has been installed.
app_folder = output_root / app_name
staging = output_root / ('.' + app_name + '-customer-exports-staging')
customer_exports = app_folder / 'build-kit' / 'dist' / 'customers'
if staging.exists():
    shutil.rmtree(staging)
if customer_exports.is_dir():
    shutil.copytree(customer_exports, staging)
env = dict(os.environ)
env['PYTHONPATH'] = os.pathsep.join([str(root / 'release-build' / 'tooling'), str(root / 'backend'), str(root / 'admin_console')])
subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--onedir', '--windowed',
    '--name', app_name, '--distpath', str(output_root), '--workpath', str(root / 'release-build' / 'admin'),
    '--specpath', str(root / 'release-build'), '--paths', str(root / 'backend'), '--paths', str(root / 'admin_console'),
    str(root / 'admin_console' / 'app.py')], check=True, env=env, cwd=root)

# Build kit belongs only to the vendor package. Allowlist source; never copy .env,
# business databases, exports, signing keys or the administrator's customer records.
kit = output_root / app_name / 'build-kit'
for folder in ['backend', 'packaging']:
    for source in (root / folder).glob('*.py'):
        if source.name.startswith('test_'): continue
        target = kit / folder / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
for relative in ['frontend/build/windows/x64/runner/Release', 'frontend/assets/fonts', 'release-build/tooling']:
    shutil.copytree(root / relative, kit / relative, dirs_exist_ok=True)
shutil.copy2(root / 'backend' / 'requirements.txt', kit / 'backend' / 'requirements.txt')
shutil.copy2(root / 'VERSION.json', kit / 'VERSION.json')
if staging.is_dir():
    shutil.copytree(staging, kit / 'dist' / 'customers', dirs_exist_ok=True)
    shutil.rmtree(staging)
