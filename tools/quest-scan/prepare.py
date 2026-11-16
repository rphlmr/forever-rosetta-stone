"""Prepare a separate local probe addon for explicit quest IDs; never install or run it."""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent / 'rosetta-quest-probe'
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import get_digest, load_entity


def prepare_probe(ids, output, eg_revision='', root=ROOT, session_name=None, item_dependencies=None):
    """Write a fresh probe under ignored references, preserving every existing run directory."""
    if not ids or any(type(quest_id) is not int or quest_id < 1 for quest_id in ids):
        raise ValueError('Expected a nonempty list of positive quest IDs')

    if len(ids) != len(set(ids)):
        raise ValueError('Quest IDs must be unique')

    if eg_revision and not re.fullmatch(r'[0-9a-f]{40}', eg_revision):
        raise ValueError('Expected a full EG Link commit SHA')
    if session_name is not None and not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}', session_name):
        raise ValueError('Session name must be an ASCII identifier of at most 64 characters')

    destination = output.resolve()

    if not destination.is_relative_to((root / 'datasources/imports/quest-scan').resolve()):
        raise ValueError('Probe output must stay under datasources/imports/quest-scan, outside shipping addons')

    if destination.exists():
        raise FileExistsError('Probe output already exists; choose a new directory: ' + str(destination))

    ordered_ids = sorted(ids)
    dependencies = {}
    for key, values in (item_dependencies or {}).items():
        if not isinstance(key, str) or not key.isdecimal() or str(int(key)) != key or int(key) not in ordered_ids:
            raise ValueError('Dependency keys must be selected quest IDs')
        if not isinstance(values, list) or not values or len(values) > 100 or any(type(v) is not int or v < 1 for v in values) or len(values) != len(set(values)):
            raise ValueError('Each dependency list must contain 1–100 unique positive item IDs')
        dependencies[key] = sorted(values)
    records = {str(quest_id): load_entity(root, 'quests', quest_id) for quest_id in ordered_ids}
    queue = {
        'ids': ordered_ids,
        'catalogHash': get_digest(records),
        'egRevision': eg_revision,
    }
    if session_name:
        queue['savedVariable'] = 'RosettaQuestProbeData_' + session_name
    if dependencies:
        queue['itemDependencies'] = dict(sorted(dependencies.items(), key=lambda entry: int(entry[0])))
    queue['hash'] = get_digest(queue)
    source = 'RosettaQuestProbeQueue = {\n'

    for key in ('hash', 'catalogHash', 'egRevision'):
        source += '    ' + key + ' = ' + json.dumps(queue[key]) + ',\n'

    source += '    ids = {' + ', '.join(map(str, ordered_ids)) + '},\n'
    source += '    itemDependencies = {\n'
    for key, values in queue.get('itemDependencies', {}).items():
        source += '        [' + key + '] = {' + ', '.join(map(str, values)) + '},\n'
    source += '    },\n}\n'
    destination.mkdir(parents=True)

    for filename in ('probe.lua', 'rosetta-quest-probe.toc'):
        shutil.copy2(SOURCE / filename, destination / filename)
        if session_name:
            path = destination / filename
            path.write_text(re.sub(r'\bRosettaQuestProbeData\b', queue['savedVariable'],
                                   path.read_text(encoding='utf-8')), encoding='utf-8')

    (destination / 'queue.lua').write_text(source, encoding='utf-8')

    return queue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids', type=int, nargs='+', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--eg-revision', default='')
    parser.add_argument('--session-name', help='Use a separate SavedVariables name for a new capture session')
    parser.add_argument('--item-dependencies', type=Path, help='JSON object mapping selected quest IDs to candidate item ID arrays')
    args = parser.parse_args()

    try:
        dependencies = json.loads(args.item_dependencies.read_text(encoding='utf-8')) if args.item_dependencies else None
        if dependencies is not None and not isinstance(dependencies, dict):
            raise ValueError('Item dependencies must be a JSON object')
        queue = prepare_probe(args.ids, args.output, args.eg_revision, session_name=args.session_name, item_dependencies=dependencies)
    except (OSError, ValueError) as error:
        parser.exit(1, f'Cannot prepare local quest probe: {error}\n')

    print(f'Prepared {len(queue["ids"])} quest IDs at {args.output}; not installed or started.')


if __name__ == '__main__':
    main()
