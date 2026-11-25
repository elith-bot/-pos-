"""Read-only, stable SHA-256 comparison of large personal-file candidates."""
import hashlib
import json
from collections import defaultdict
from pathlib import Path

report = Path(__file__).resolve().parents[1]/'release-build/disk-audit'
data = json.loads((report/'inventory.json').read_text(encoding='utf-8'))
personal = [Path.home()/n for n in ['Downloads','Desktop','Documents','Videos','Pictures']]
skip = {'node_modules','build','dist','release-build','.git','.venv','venv','_internal','.dart_tool'}
extensions = {'.iso','.zip','.rar','.7z','.exe','.msi','.mp4','.mkv','.mov','.pdf','.docx','.xlsx','.psd','.prproj','.vdi'}
matches, errors = [], []
for size, names in data['duplicate_candidates'].items():
    samples = defaultdict(list)
    seen = set()
    for name in names:
        path = Path(name)
        if path.suffix.lower() not in extensions or any(p.lower() in skip for p in path.parts): continue
        if not any(path.is_relative_to(root) for root in personal) or not path.is_file(): continue
        try:
            stat = path.stat()
            identity = (stat.st_dev,stat.st_ino)
            if identity in seen: continue
            seen.add(identity)
            with path.open('rb') as file:
                digest = hashlib.sha256()
                for offset in [0,max(0,stat.st_size//2-32768),max(0,stat.st_size-65536)]:
                    file.seek(offset);digest.update(file.read(65536))
            samples[digest.digest()].append((path,stat.st_size,stat.st_mtime_ns))
        except OSError: errors.append(str(path))
    for group in samples.values():
        if len(group)<2: continue
        hashes = defaultdict(list)
        for path, length, modified in group:
            try:
                with path.open('rb') as file:
                    digest = hashlib.file_digest(file,'sha256').hexdigest()
                stat = path.stat()
                if stat.st_size == length and stat.st_mtime_ns == modified:
                    hashes[digest].append(str(path))
            except OSError: errors.append(str(path))
        for digest, paths in hashes.items():
            if len(paths)>1: matches.append(dict(bytes=int(size),copies=len(paths),sha256=digest,paths=paths))
result = dict(groups=matches, unreadable=errors, potential_reclaim=sum(x['bytes']*(x['copies']-1) for x in matches))
(report/'duplicates.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result))
