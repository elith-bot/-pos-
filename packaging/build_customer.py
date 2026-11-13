"""Allowlisted customer packaging; never copy the development DB, .env or admin keys."""
import argparse
import json
import hashlib
import os
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
sys.path.insert(0, str(ROOT / 'release-build' / 'tooling'))
from license_protocol import verify
from distribution_names import application_name
from compile_backend import compile_backend


def build(edition, compiler=None):
    edition = Path(edition).resolve()
    public_key = (edition / 'license-public.pem').read_bytes()
    manifest = verify((edition / 'deployment.pos').read_text(encoding='utf-8'), public_key, 'deployment')
    edition_id = manifest['edition_id']
    display_name = application_name(manifest)
    if not re.fullmatch('[a-f0-9]{32}', edition_id): raise ValueError('Invalid edition identifier')
    if not (ROOT / 'frontend' / 'build' / 'windows' / 'x64' / 'runner' / 'Release' / 'starter_app.exe').is_file():
        raise RuntimeError('ابنِ واجهة Flutter Windows أولاً: flutter build windows --release --dart-define=POS_PACKAGED=true')
    native_release = ROOT / 'frontend/build/windows/x64/runner/Release'
    proof = native_release / 'protection.json'
    if not proof.is_file(): raise RuntimeError('ابنِ واجهة الحماية أولاً باستخدام packaging/build_native.py')
    protection = json.loads(proof.read_text(encoding='utf-8'))
    if protection.get('obfuscated') is not True or protection.get('app_sha256') != hashlib.sha256((native_release/'data/app.so').read_bytes()).hexdigest():
        raise RuntimeError('واجهة الكاشير لا تطابق بناء الحماية. أعد بناء الواجهة.')
    compiler = compiler or shutil.which('ISCC.exe')
    if not compiler:
        for root in [os.environ.get('ProgramFiles(x86)', ''), os.environ.get('ProgramFiles', ''), str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs')]:
            candidate = Path(root) / 'Inno Setup 6' / 'ISCC.exe'
            if candidate.is_file(): compiler = str(candidate); break
    if not compiler: raise RuntimeError('يتطلب إنشاء ملف التنصيب تثبيت Inno Setup 6 على جهاز الإدارة.')
    work = ROOT / 'release-build' / (edition_id + '-' + uuid.uuid4().hex[:8])
    work.mkdir(parents=True)
    # Public trust anchor is embedded in compiled Python bytecode, not loaded from an editable PEM.
    (work / 'trusted_license.py').write_text(f'PUBLIC_KEY = {public_key!r}\nEDITION_ID = {edition_id!r}\nAPP_NAME = {display_name!r}\n', encoding='utf-8')
    shutil.copyfile(ROOT / 'packaging' / 'customer_entry.py', work / 'customer_entry.py')
    compiled, hidden_imports = compile_backend(work)
    (work/'trusted_license.py').rename(work/'trusted_license.py.source')
    env = dict(os.environ)
    env['PYTHONPATH'] = os.pathsep.join([str(ROOT / 'release-build' / 'tooling'), str(compiled), str(work)])
    subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--onedir', '--windowed', '--uac-admin',
        '--name', 'POSCashier', '--distpath', str(work / 'dist'), '--workpath', str(work / 'build'), '--specpath', str(work),
        '--paths', str(compiled), '--paths', str(work),
        *[value for module in hidden_imports for value in ('--hidden-import', module)],
        '--hidden-import', 'sqlalchemy.dialects.sqlite', '--hidden-import', 'sqlalchemy.dialects.mysql.pymysql',
        '--add-data', str(edition / 'deployment.pos') + ';.',
        '--add-data', str(ROOT / 'frontend' / 'build' / 'windows' / 'x64' / 'runner' / 'Release') + ';native',
        '--add-data', str(ROOT / 'frontend' / 'assets' / 'fonts' / 'NotoSansArabic.ttf') + ';fonts',
        str(work / 'customer_entry.py')], check=True, env=env, cwd=ROOT)
    from PyInstaller.archive.readers import CArchiveReader
    archive = CArchiveReader(str(work/'dist/POSCashier/POSCashier.exe'))
    pyz_name = next(name for name in archive.toc if name.endswith('.pyz'))
    pyz = archive.open_embedded_archive(pyz_name)
    compiled_names = {p.name.split('.')[0] for p in compiled.glob('*.pyd')}
    if compiled_names.intersection(pyz.toc):
        raise RuntimeError('رفض التصدير: وُجد كود Python قابل للاستخراج بدلاً من المكتبات المترجمة.')
    for name in compiled_names:
        if not list((work/'dist/POSCashier/_internal').glob(name+'.*.pyd')):
            raise RuntimeError('Compiled backend missing from bundle: '+name)
    (work/'protection-report.json').write_text(json.dumps({'compiled_modules': sorted(compiled_names), 'first_party_python_in_archive': False, 'flutter_obfuscated': True}, indent=2),encoding='utf-8')
    # Bundle the native UI's C++ runtime so customers do not need build tools.
    native_folder = work / 'dist' / 'POSCashier' / '_internal' / 'native'
    for program_root in [os.environ.get('ProgramFiles(x86)', ''), os.environ.get('ProgramFiles', '')]:
        vs = Path(program_root) / 'Microsoft Visual Studio' / '2022'
        for runtime in vs.glob('*/VC/Redist/MSVC/*/x64/Microsoft.VC143.CRT/*.dll'):
            shutil.copy2(runtime, native_folder / runtime.name)
    packaged = work / 'dist' / 'POSCashier'
    (packaged / 'POSCashier.exe').rename(packaged / (display_name + '.exe'))
    (native_folder / 'starter_app.exe').rename(native_folder / (display_name + '.exe'))
    output = ROOT / 'dist' / 'customers' / display_name
    output.mkdir(parents=True, exist_ok=True)
    # Customer strings are never interpolated into installer directives or shell commands.
    script = work / 'installer.iss'
    script.write_text(f'''[Setup]
AppId=POSCashier-{edition_id}
AppName={display_name}
AppVersion=1.1.0
DefaultDirName={{autopf}}\\{display_name}
DefaultGroupName={display_name}
OutputDir={output}
OutputBaseFilename={display_name}-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={{app}}\\{display_name}.exe
[Files]
Source: "{work / 'dist' / 'POSCashier' / '*'}"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{{group}}\\{display_name}"; Filename: "{{app}}\\{display_name}.exe"
Name: "{{autodesktop}}\\{display_name}"; Filename: "{{app}}\\{display_name}.exe"
[Run]
Filename: "{{app}}\\{display_name}.exe"; Description: "تشغيل {display_name}"; Flags: nowait postinstall skipifsilent
''', encoding='utf-8-sig')
    subprocess.run([compiler, str(script)], check=True, cwd=ROOT)
    return output / f'{display_name}-Setup.exe'


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'): sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if hasattr(sys.stderr, 'reconfigure'): sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser()
    parser.add_argument('edition', type=Path)
    parser.add_argument('--iscc')
    args = parser.parse_args()
    print(build(args.edition, args.iscc))
