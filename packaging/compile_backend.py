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
    import tempfile
    with tempfile.TemporaryDirectory(prefix='moon-cc-') as temporary:
        stage = Path(temporary).resolve()
        source_folder = stage/'src'
        source_folder.mkdir()
        for source in sources: shutil.copy2(source, source_folder/source.name)
        setup = stage/'setup.py'
        setup.write_text("from setuptools import setup\nfrom Cython.Build import cythonize\n" +
            "setup(ext_modules=cythonize(" + repr([p.name for p in sources]) +
            ", build_dir=" + repr(str(stage/'c')) +
            ", compiler_directives={'language_level':3,'binding':True,'embedsignature':False,'emit_code_comments':False,'annotation_typing':False}, annotate=False))\n", encoding='utf-8')
        env = dict(os.environ)
        env['PYTHONUTF8'] = '1'
        env['CL'] = env.get('CL', '') + ' /utf-8'
        env['PYTHONPATH'] = str(ROOT/'release-build/tooling')
        subprocess.run([sys.executable,str(setup),'build_ext','--build-lib',str(stage/'bin'),'--build-temp',str(stage/'obj')],env=env,cwd=source_folder,check=True)
        for library in (stage/'bin').glob('*.pyd'):
            shutil.copy2(library, compiled/library.name)
    modules = [p.stem for p in sources]
    for module in modules:
        if not list(compiled.glob(module+'.*.pyd')): raise RuntimeError('Missing compiled module: '+module)
    return compiled, sorted(imports | set(modules))
