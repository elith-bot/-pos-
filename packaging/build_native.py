"""Build Flutter Windows through an ASCII staging path for Windows tool compatibility."""
import os
import hashlib
import json
import uuid
import shutil
import subprocess
import tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
flutter = shutil.which('flutter.bat') or 'C:/flutter/bin/flutter.bat'
stage = Path(tempfile.mkdtemp(prefix='pos-native-')) / 'frontend'
shutil.copytree(root/'frontend',stage,ignore=shutil.ignore_patterns('build','.dart_tool','.git','ephemeral','.plugin_symlinks'))
subprocess.run([flutter,'--no-version-check','pub','get'],cwd=stage,check=True)
symbols = stage.parent/'symbols'
symbols.mkdir(parents=True,exist_ok=True)
subprocess.run([flutter,'--no-version-check','build','windows','--release','--obfuscate','--split-debug-info='+str(symbols),'--dart-define=POS_PACKAGED=true'],cwd=stage,check=True)
output = Path('build/windows/x64/runner/Release')
shutil.copytree(stage/output,root/'frontend'/output,dirs_exist_ok=True)
shutil.copytree(symbols,root/'release-build'/'symbols'/uuid.uuid4().hex)
payload = root/'frontend'/output/'data'/'app.so'
(root/'frontend'/output/'protection.json').write_text(json.dumps({'obfuscated':True,'app_sha256':hashlib.sha256(payload.read_bytes()).hexdigest()}),encoding='utf-8')
print('Obfuscated Windows EXE built successfully; debug symbols kept vendor-side')
