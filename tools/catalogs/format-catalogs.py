"""Check or write the shared catalog JSON format without changing JSON values."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import dump_json, parse_json


def catalog_paths(root, paths=()):
    directory = (Path(root) / 'catalogs').resolve()
    selected = set()
    for argument in paths or (directory,):
        path = Path(argument).resolve()
        if not path.is_relative_to(directory) or not path.exists():
            raise ValueError('Expected an existing path under catalogs/: ' + str(path))
        candidates = path.rglob('*.json') if path.is_dir() else (path,)
        for candidate in candidates:
            if candidate.suffix != '.json' or not candidate.resolve().is_relative_to(directory):
                raise ValueError('Expected a catalog JSON file: ' + str(candidate))
            selected.add(candidate)
    return sorted(selected)


def format_catalogs(root, paths=(), write=False):
    root = Path(root).resolve()
    result = {'checkedFiles': 0, 'changedFiles': 0, 'writtenFiles': 0, 'examples': []}
    for path in catalog_paths(root, paths):
        raw = path.read_bytes()
        value = parse_json(raw, path)
        formatted = dump_json(value).encode('utf-8')
        result['checkedFiles'] += 1
        if raw == formatted:
            continue
        result['changedFiles'] += 1
        if len(result['examples']) < 20:
            result['examples'].append(str(path.relative_to(root)))
        if write:
            if parse_json(formatted, path) != value:
                raise ValueError('Formatting changed JSON values: ' + str(path))
            if path.read_bytes() != raw:
                raise ValueError('Concurrent catalog edit: ' + str(path))
            path.write_bytes(formatted)
            result['writtenFiles'] += 1
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true', help='Fail if any selected JSON needs formatting')
    mode.add_argument('--write', action='store_true', help='Normalize formatting; verify JSON values before each write')
    parser.add_argument('paths', nargs='*', type=Path, help='Catalog files/directories; defaults to all catalogs')
    args = parser.parse_args()
    try:
        result = format_catalogs(ROOT, args.paths, write=args.write)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')
    print(json.dumps(result, ensure_ascii=False))
    if args.check and result['changedFiles']:
        parser.exit(1, 'Run python3 tools/catalogs/format-catalogs.py --write to normalize catalog JSON.\n')


if __name__ == '__main__':
    main()
