"""Prepare an offline, local-only source probe; never install or start it."""

import argparse
import csv
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent / 'rosetta-source-probe'
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import get_digest, load_catalog, load_entity
sys.path.insert(0, str(ROOT / 'datasources'))
from datasources.wago.loader import validate_csv


FIELDS = {
    'quests': ['title', 'objectiveLines'],
    'items': ['name', 'description'],
    'spells': ['name', 'description', 'subtext'],
    'areas': ['name'],
    'maps': ['name'],
    'factions': ['modern', 'legacy'],
}
CLIENT_BUILD = '1.60.1.70888'
CLIENT_LOCALES = frozenset(('enUS', 'deDE', 'esES', 'esMX', 'frFR', 'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW'))


def load_full_inventory(snapshot, quest_ids):
    """Read pinned client tables and an attributed known-quest inventory."""
    manifest = json.loads((snapshot / 'manifest.json').read_text(encoding='utf-8'))
    if manifest.get('build') != CLIENT_BUILD:
        raise ValueError(f'Expected Wago build {CLIENT_BUILD}, got {manifest.get("build")}')
    if manifest.get('complete') is not True or manifest.get('stoppedEarly') is not False:
        raise ValueError(f'Incomplete Wago snapshot: {snapshot}')

    inventory = {'items': set(), 'spells': set(), 'quests': set()}
    sources = {}
    for table, kind in (('Item', 'items'), ('ItemSparse', 'items'), ('Spell', 'spells'), ('SpellName', 'spells')):
        results = [result for result in manifest['results'] if result['table'] == table]
        required_locales = {'enUS'} if table == 'Item' else CLIENT_LOCALES
        if not required_locales.issubset({result['locale'] for result in results}):
            raise ValueError(f'Missing required Wago locales for {table}')

        table_ids = set()
        files = []
        seen_locales = set()
        for result in results:
            locale = result['locale']
            filename = f'{table}.{CLIENT_BUILD}.{locale}.csv'
            if (locale not in CLIENT_LOCALES or locale in seen_locales
                    or result.get('file') != filename or Path(filename).name != filename
                    or result.get('status') not in ('downloaded', 'existing')):
                raise ValueError(f'Incomplete Wago table: {table}/{result["locale"]}')
            seen_locales.add(locale)
            path = snapshot / filename
            content = path.read_bytes()
            digest = hashlib.sha256(content).hexdigest()
            if digest != result.get('sha256'):
                raise ValueError(f'Wago table checksum mismatch: {path}')
            if validate_csv(content, table) != result['rows']:
                raise ValueError(f'Wago table row count mismatch: {path}')
            with path.open(encoding='utf-8-sig', newline='') as stream:
                for row in csv.DictReader(stream):
                    value = int(row['ID'])
                    if value > 0:
                        table_ids.add(value)
            files.append({'file': result['file'], 'locale': result['locale'], 'sha256': digest})
        inventory[kind].update(table_ids)
        sources[table] = {'build': CLIENT_BUILD, 'files': files, 'idCount': len(table_ids)}

    quest_inventory = json.loads(quest_ids.read_text(encoding='utf-8'))
    for name in ('questieForever', 'egQuests70862', 'egHistoricalQuestsAndObjectives'):
        source = quest_inventory['sources'][name]
        if not source.get('revision') or not isinstance(source.get('ids'), list):
            raise ValueError(f'Missing pinned quest source provenance or IDs: {name}')
        ids = source['ids']
        if any(type(value) is not int or value < 1 for value in ids):
            raise ValueError(f'Invalid quest IDs in {name}')
        inventory['quests'].update(ids)
        sources[name] = {key: value for key, value in source.items() if key != 'ids'}
        sources[name]['idCount'] = len(set(ids))
    sources['questInventory'] = {'sha256': hashlib.sha256(quest_ids.read_bytes()).hexdigest()}
    return inventory, sources


def to_lua(value):
    if isinstance(value, dict):
        return '{' + ', '.join('[' + to_lua(key) + '] = ' + to_lua(item) for key, item in value.items()) + '}'

    if isinstance(value, list):
        return '{' + ', '.join(to_lua(item) for item in value) + '}'

    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)

    if isinstance(value, int):
        return str(value)

    raise ValueError('Unsupported queue value: ' + repr(value))


def prepare_probe(output, selections, include_globals=False, root=ROOT, *, inventory=None, sources=None, spell_context=False, global_keys=(), unowned_spells=()):
    """Create a new queue and addon copy under datasources/imports/source-scan."""
    destination = output.resolve()

    if spell_context and (inventory is not None or include_globals or global_keys or unowned_spells
                          or any(ids for kind, ids in selections.items() if kind not in ('items', 'spells'))
                          or not selections.get('spells')):
        raise ValueError('Spell context requires explicit spells and optional items only')

    if not destination.is_relative_to((root / 'datasources/imports/source-scan').resolve()):
        raise ValueError('Probe output must stay under datasources/imports/source-scan')

    if destination.exists():
        raise FileExistsError('Probe output already exists: ' + str(destination))

    records = {}
    jobs = {}

    for entity_id in sorted(set(unowned_spells)):
        if type(entity_id) is not int or entity_id < 1:
            raise ValueError('Expected positive spell ID: ' + str(entity_id))
        if load_entity(root, 'spells', entity_id) is not None:
            raise ValueError(f'Use --spells for maintained record: {entity_id}')
        records[f'unowned-spells/{entity_id}'] = {'explicitUnownedId': entity_id}
        jobs[('spells', entity_id)] = {'kind': 'spells', 'id': entity_id, 'fields': FIELDS['spells']}

    for kind, ids in selections.items():
        if kind not in (*FIELDS, 'talents'):
            raise ValueError('Unsupported kind: ' + kind)

        for entity_id in sorted(set(ids)):
            if type(entity_id) is not int or entity_id < 1:
                raise ValueError('Expected positive entity ID: ' + str(entity_id))

            entity = load_entity(root, kind, entity_id)

            if entity is None:
                raise ValueError(f'Catalog record does not exist: {kind}/{entity_id}')

            records[f'{kind}/{entity_id}'] = entity

            if kind == 'talents':
                for rank, spell_id in enumerate(entity.get('spellRankIds', []), start=1):
                    if type(spell_id) is not int or spell_id < 1:
                        raise ValueError(f'Invalid talent rank spell ID: {entity_id}/{rank}: {spell_id}')
                    job = jobs.setdefault(('spells', spell_id), {
                        'kind': 'spells', 'id': spell_id, 'fields': FIELDS['spells'],
                    })
                    job.setdefault('talentIds', []).append(entity_id)
                    job.setdefault('talentRanks', []).append({'talentId': entity_id, 'rank': rank})
            else:
                job = jobs.setdefault((kind, entity_id), {'kind': kind, 'id': entity_id, 'fields': FIELDS[kind]})
                if kind == 'spells' and spell_context:
                    english = entity.get('locales', {}).get('enUS', {})
                    templates = [english.get('description', ''), english.get('auraDescription', '')]
                    templates.extend(entity.get('tooltipData', {}).get('variables', []))
                    job['captureContext'] = 1
                    job['knownSpellIds'] = sorted({int(value) for template in templates if isinstance(template, str)
                                                   for value in re.findall(r'\$\?s(\d+)', template)})

    for kind, ids in (inventory or {}).items():
        for entity_id in sorted(ids):
            jobs.setdefault((kind, entity_id), {'kind': kind, 'id': entity_id, 'fields': FIELDS[kind]})

    if include_globals:
        fixture = json.loads((root / 'tests/fixtures/tooltip-client-strings.json').read_text(encoding='utf-8'))
        records['globalKeys'] = sorted(fixture['strings'])

        for key in records['globalKeys']:
            jobs[('globals', key)] = {'kind': 'globals', 'key': key, 'fields': ['value']}

    if global_keys:
        allowed = {f'FACTION_STANDING_LABEL{i}' for i in range(1, 9)}
        if not set(global_keys) <= allowed:
            raise ValueError('Unsupported explicit global key')
        records['explicitGlobalKeys'] = sorted(set(global_keys))
        for key in records['explicitGlobalKeys']:
            jobs[('globals', key)] = {'kind': 'globals', 'key': key, 'fields': ['value']}

    if not jobs:
        raise ValueError('Select at least one catalog entity or --globals')

    config = load_catalog(root, 'quests', ids={})
    locales = [locale for locale in config['locales'] if locale not in config['rosettaLocales']]
    ordered_jobs = [jobs[key] for key in sorted(jobs)]
    queue = {
        'schemaVersion': 1,
        'catalogHash': get_digest(records),
        'profiles': {locale: {'jobs': ordered_jobs} for locale in locales},
    }
    if sources is not None:
        queue['inventory'] = {
            'sources': sources,
            'limitations': ['Known quest IDs are a source union, not an enumeration of all server quest IDs.'],
            'jobCounts': {kind: sum(job['kind'] == kind for job in ordered_jobs) for kind in FIELDS},
        }
    queue['hash'] = get_digest(queue)
    destination.mkdir(parents=True)

    for path in SOURCE.iterdir():
        if path.is_file() and path.name != 'queue.lua':
            shutil.copy2(path, destination / path.name)

    profiles = '{' + ', '.join('[' + to_lua(locale) + '] = { jobs = jobs }' for locale in locales) + '}'
    lua = 'local jobs = {}\n'

    for offset in range(0, len(ordered_jobs), 500):
        batch = to_lua(ordered_jobs[offset:offset + 500])
        lua += 'do local function append() local batch = ' + batch
        lua += ' for _, job in ipairs(batch) do jobs[#jobs + 1] = job end end append() end\n'

    lua += 'RosettaSourceProbeQueue = { schemaVersion = 1, catalogHash = ' + to_lua(queue['catalogHash'])
    lua += ', hash = ' + to_lua(queue['hash']) + ', profiles = ' + profiles + ' }\n'
    (destination / 'queue.lua').write_text(lua, encoding='utf-8')
    (destination / 'queue.json').write_text(json.dumps(queue, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    return queue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--all', action='store_true', help='Select every maintained ID in scannable catalogs')
    parser.add_argument('--client-snapshot', type=Path, help='Pinned Wago 1.60.1.70888 snapshot directory')
    parser.add_argument('--quest-ids', type=Path, help='Attributed QuestieDB and EG known-quest inventory JSON')
    parser.add_argument('--globals', action='store_true', help='Include checked-in GlobalStrings inventory')
    parser.add_argument('--global-keys', nargs='+', default=[], help='Explicit faction standing label keys')
    parser.add_argument('--unowned-spells', nargs='+', type=int, default=[], help='Explicit spell IDs without catalog records')
    parser.add_argument('--spell-context', action='store_true', help='Capture character context for explicit spell jobs')

    for kind in (*FIELDS, 'talents'):
        parser.add_argument('--' + kind, nargs='+', type=int, default=[])

    args = parser.parse_args()
    selections = {kind: getattr(args, kind) for kind in (*FIELDS, 'talents')}

    try:
        if args.all:
            if args.spell_context or args.global_keys or args.unowned_spells:
                raise ValueError('--spell-context, --global-keys and --unowned-spells require explicit selection, not --all')
            if selections['factions']:
                raise ValueError('--factions requires explicit selection, not --all')
            if not args.client_snapshot or not args.quest_ids:
                raise ValueError('--all requires --client-snapshot and --quest-ids')
            for kind in selections:
                if kind == 'factions':
                    continue
                selections[kind] = sorted(set(selections[kind]) | {
                    int(path.stem) for path in (ROOT / 'catalogs' / kind).glob('[0-9]*.json')
                })
            inventory, sources = load_full_inventory(args.client_snapshot, args.quest_ids)
            queue = prepare_probe(args.output, selections, True, inventory=inventory, sources=sources)
        else:
            if args.client_snapshot or args.quest_ids:
                raise ValueError('--client-snapshot and --quest-ids require --all')
            queue = prepare_probe(args.output, selections, args.globals, spell_context=args.spell_context,
                                  global_keys=args.global_keys, unowned_spells=args.unowned_spells)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Cannot prepare local source probe: {error}\n')

    print(f'Prepared {len(next(iter(queue["profiles"].values()))["jobs"])} jobs per locale at {args.output}; '
          'not installed or started.')


if __name__ == '__main__':
    main()
