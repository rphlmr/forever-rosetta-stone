"""Compare shipped name lookups with the maintained catalogs."""

import json
import sys
from collections import Counter, defaultdict

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog


def native_name(entity, locale):
    localized = entity.get('locales', {}).get(locale, {})
    metadata = localized.get('translationMetadata', {}).get('fields', {}).get('name', {})
    return entity.get('sourceNames', {}).get(locale) or (
        localized.get('name') if metadata.get('origin') in ('original', 'community') else None
    )


def lua_rows(lua, rows):
    return lua.table_from([lua.table_from(row) for row in rows])


def run_matrix():
    config = load_catalog(ROOT, 'quests', ids={})
    locales = config['locales']
    clients = [locale for locale in locales if locale not in config['rosettaLocales']]
    entities = {}
    for catalog in ('npcs', 'areas', 'talents', 'items'):
        entities.update(load_catalog(ROOT, catalog)['catalogs'])

    lua = LuaRuntime(encoding=None)
    install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
    codec = lua.globals().C_EncodingUtil
    deserialize = codec[b'DeserializeCBOR']
    decoded = {}

    def deserialize_cached(value):
        if value not in decoded:
            decoded[value] = deserialize(value)
        return decoded[value]

    codec[b'DeserializeCBOR'] = deserialize_cached
    db = load_database(lua)
    check_names = lua.eval(b'''
        function(db, method, locale, rows)
            local failures = {}
            for _, row in ipairs(rows) do
                local actual = db[method](db, row[1], locale)
                if actual ~= row[2] then
                    failures[#failures + 1] = { row[1], row[2], actual or false }
                end
            end
            return failures
        end
    ''')
    check_reverse = lua.eval(b'''
        function(db, method, source, target, rows)
            local failures = {}
            for _, row in ipairs(rows) do
                local actual = db[method](db, row[1], source, target)
                if actual ~= row[2] then
                    failures[#failures + 1] = { row[1], row[2] or false, actual or false }
                end
            end
            return failures
        end
    ''')
    methods = {'npcs': 'GetNpcName', 'areas': 'GetAreaName', 'maps': 'GetMapName',
               'talents': 'GetTalentName'}
    report = {'missingEntitySource': [], 'missingTarget': [], 'missingSource': [], 'unsupportedReverse': [],
              'missingReverseTarget': [], 'ambiguous': [], 'failures': []}
    counts = Counter()

    for kind, records in entities.items():
        if kind == 'items':
            continue
        counts[kind + ' entities'] = len(records)
        unnamed = {entity_id for entity_id, entity in records.items()
                   if not any(localized.get('name') for localized in entity.get('locales', {}).values())
                   and not any(entity.get('sourceNames', {}).values())}
        for entity_id in sorted(unnamed):
            report['missingEntitySource'].append({
                'kind': kind, 'id': entity_id, 'field': 'name', 'clients': clients, 'targets': locales,
                'reason': 'no name in any maintained locale or native source',
            })
        for locale in locales:
            rows = []
            for entity_id, entity in records.items():
                localized = entity.get('locales', {}).get(locale, {})
                name = localized.get('name')
                if name:
                    rows.append((int(entity_id), name.encode()))
                elif entity_id not in unnamed:
                    report['missingTarget'].append({
                        'kind': kind, 'id': entity_id, 'field': 'name', 'target': locale,
                        'reason': 'no maintained target name',
                    })
            failures = check_names(db, methods[kind].encode(), locale.encode(), lua_rows(lua, rows))
            counts['lookup checks'] += len(rows)
            for _, failure in failures.items():
                report['failures'].append({
                    'kind': kind, 'id': str(failure[1]), 'field': 'name', 'target': locale,
                    'reason': 'ID lookup differs from catalog', 'expected': failure[2].decode(),
                    'actual': failure[3].decode() if failure[3] else None,
                })

        for entity_id, entity in records.items():
            if entity_id in unnamed:
                if kind != 'areas':
                    report['unsupportedReverse'].append({
                        'kind': kind, 'id': entity_id, 'field': 'name', 'clients': clients,
                        'targets': locales, 'reason': 'no public reverse name API',
                    })
                continue
            missing = [client for client in clients if not native_name(entity, 'enUS' if client == 'enGB' else client)]
            if missing:
                report['missingSource'].append({
                    'kind': kind, 'id': entity_id, 'field': 'name', 'clients': missing,
                    'targets': locales, 'reason': 'no native or community source name',
                })
            if kind != 'areas':
                report['unsupportedReverse'].append({
                    'kind': kind, 'id': entity_id, 'field': 'name', 'clients': clients,
                    'targets': locales, 'reason': 'no public reverse name API',
                })

    counts['items entities'] = len(entities['items'])
    report['counts'] = dict(counts)
    output = ROOT / 'datasources/imports/translation-matrix/names.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Name matrix:', dict(counts), 'gaps:', {key: len(value) for key, value in report.items()
                                                 if isinstance(value, list)})
    if report['failures']:
        raise AssertionError(f'{len(report["failures"])} name matrix failures; first 20: '
                             + json.dumps(report['failures'][:20], ensure_ascii=False))
    return report['counts']


if __name__ == '__main__':
    run_matrix()
