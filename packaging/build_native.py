"""Build Flutter Windows through an ASCII staging path for Windows tool compatibility."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
flutter = shutil.which('flutter.bat') or 'C:/flutter/bin/flutter.bat'
stage = Path(tempfile.mkdtemp(prefix='pos-native-')) / 'frontend'
shutil.copytree(root/'frontend',stage,ignore=shutil.ignore_patterns('build','.dart_tool','.git','ephemeral','.plugin_symlinks'))
subprocess.run([flutter,'--no-version-check','pub','get'],cwd=stage,check=True)
subprocess.run([flutter,'--no-version-check','build','windows','--release','--dart-define=POS_PACKAGED=true'],cwd=stage,check=True)
output = Path('build/windows/x64/runner/Release')
shutil.copytree(stage/output,root/'frontend'/output,dirs_exist_ok=True)
print('Windows EXE built successfully')
