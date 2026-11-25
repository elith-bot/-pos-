"""Read-only disk inventory; skips junctions and does not open file contents."""
import heapq
import json
import os
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
report = root / 'release-build' / 'disk-audit'
report.mkdir(parents=True, exist_ok=True)
totals, files, errors, duplicate_sizes = {}, [], [], {}
started = time.time()

def scan(path):
    size = 0
    try:
        with os.scandir(path) as entries:
            for entry in entries:
                try:
                    stat = entry.stat(follow_symlinks=False)
                    if entry.is_dir(follow_symlinks=False):
                        if getattr(stat, 'st_file_attributes', 0) & 0x400:
                            continue
                        size += scan(entry.path)
                    elif entry.is_file(follow_symlinks=False):
                        size += stat.st_size
                        item = (stat.st_size, entry.path)
                        if len(files) < 100: heapq.heappush(files, item)
                        elif item > files[0]: heapq.heapreplace(files, item)
                        if stat.st_size >= 20 * 1024 * 1024 and not getattr(stat, 'st_file_attributes', 0) & (0x1000 | 0x40000):
                            duplicate_sizes.setdefault(stat.st_size, []).append(entry.path)
                except (OSError, RecursionError) as error:
                    if len(errors) < 100: errors.append([entry.path, str(error)])
    except OSError as error:
        if len(errors) < 100: errors.append([str(path), str(error)])
    totals[str(path)] = size
    return size

scan('C:\\')
data = dict(seconds=round(time.time()-started), directories=sorted(totals.items(), key=lambda x:x[1], reverse=True),
            largest_files=sorted(files, reverse=True), errors=errors,
            duplicate_candidates={str(k): v for k,v in duplicate_sizes.items() if len(v)>1})
(report/'inventory.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(dict(seconds=data['seconds'], top_directories=data['directories'][:45], largest_files=data['largest_files'][:25], inaccessible_examples=len(errors))))
