"""Include dependency license/notice files, preserving their relative paths."""
from pathlib import Path
import shutil
import sys

source = Path('.build/release/SourcePackages/checkouts')
destination = Path(sys.argv[1])
if not source.is_dir():
    raise SystemExit('Build the app before collecting dependency licenses.')
count = 0
for path in source.rglob('*'):
    if path.is_file() and path.name.upper().startswith(('LICENSE', 'NOTICE', 'COPYING')):
        target = destination / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        count += 1
if not count:
    raise SystemExit('No dependency licenses found; refusing to package.')
print(f'Collected {count} dependency license and notice files.')
