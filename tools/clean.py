"""Remove disposable project outputs while preserving tracked files and local credentials."""

import argparse
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = ('dist', 'docs/media/curseforge/out', 'datasources/imports')
CACHE_NAMES = {'__pycache__', '.pytest_cache', '.ruff_cache', '.mypy_cache'}


def clean(root, dry_run=False):
    root = Path(root).resolve()
    tracked = subprocess.run(
        ['git', 'ls-files', '-z'], cwd=root, check=True, capture_output=True,
    ).stdout.decode().split('\0')
    tracked = [root / name for name in tracked if name]
    candidates = [root / name for name in OUTPUTS if (root / name).exists() or (root / name).is_symlink()]
    for directory, names, files in os.walk(root, followlinks=False):
        parent = Path(directory)
        names[:] = [name for name in names if name != '.git' and parent / name not in candidates]
        for name in list(names):
            if name in CACHE_NAMES:
                candidates.append(parent / name)
                names.remove(name)
        candidates.extend(parent / name for name in files if name == '.DS_Store' or name.endswith(('.pyc', '.pyo')))
    for path in candidates:
        if any(file == path or path in file.parents for file in tracked):
            raise ValueError('Refusing to remove tracked files: ' + str(path.relative_to(root)))
    for path in candidates:
        print(('Would remove ' if dry_run else 'Removing ') + str(path.relative_to(root)))
        if dry_run:
            continue
        if path.is_symlink() or path.is_file():
            path.unlink()
        else:
            shutil.rmtree(path)
    return len(candidates)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true', help='List disposable outputs without deleting them')
    options = parser.parse_args()
    clean(ROOT, options.dry_run)


if __name__ == '__main__':
    main()
