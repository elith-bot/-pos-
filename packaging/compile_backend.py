"""Compile first-party backend modules; generated C/PDB/sources stay vendor-side."""
import ast
import json
import os
import subprocess
import sys
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def compile_backend(work):
    work = Path(work)
    compiled = work / 'compiled'
    compiled.mkdir(parents=True, exist_ok=True)
    sources = [p for p in (ROOT/'backend').glob('*.py') if not p.name.startswith('test_') and p.name not in {'mcp_server.py'}]
    sources += [work/'trusted_license.py']
    # Hide no imports from the packager: C extensions are opaque to its Python scanner.
    imports = set()
    for source in sources:
        for node in ast.walk(ast.parse(source.read_text(encoding='utf-8'))):
            if isinstance(node, ast.Import): imports.update(n.name for n in node.names)
            if isinstance(node, ast.ImportFrom) and node.module: imports.add(node.module)
    source_folder = work/'src'
    source_folder.mkdir(exist_ok=True)
    for source in sources: shutil.copy2(source, source_folder/source.name)
    setup = work/'compile_setup.py'
    setup.write_text("from setuptools import setup, Extension\nfrom Cython.Build import cythonize\n" +
        "setup(ext_modules=cythonize(" + repr([p.name for p in sources]) +
        ", build_dir=" + repr(str(work/'generated-c')) +
        ", compiler_directives={'language_level':3,'binding':True,'embedsignature':False,'emit_code_comments':False,'annotation_typing':False}, annotate=False))\n", encoding='utf-8')
    env = dict(os.environ)
    env['PYTHONUTF8'] = '1'
    env['CL'] = env.get('CL', '') + ' /utf-8'
    env['PYTHONPATH'] = str(ROOT/'release-build/tooling')
    subprocess.run([sys.executable,str(setup),'build_ext','--build-lib',str(compiled),'--build-temp',str(work/'objects')],env=env,cwd=source_folder,check=True)
    modules = [p.stem for p in sources]
    for module in modules:
        if not list(compiled.glob(module+'.*.pyd')): raise RuntimeError('Missing compiled module: '+module)
    return compiled, sorted(imports | set(modules))
