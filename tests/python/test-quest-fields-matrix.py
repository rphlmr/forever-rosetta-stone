"""Compare maintained quest fields with the built Lua database."""

import json
import sys
from collections import Counter

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES, indexed_client_targets
from matrix_classification import summarize_report


FIELDS = ('title', 'summary', 'description', 'eventObjectiveLabel', 'objectiveLines')
SOURCE_FIELDS = ('title', 'summary', 'description')


def from_lua(value):
    if hasattr(value, 'items'):
        items = dict(value.items())
        if set(items) == set(range(1, len(items) + 1)):
            return [from_lua(items[index]) for index in range(1, len(items) + 1)]
        return {key.decode() if isinstance(key, bytes) else key: from_lua(item) for key, item in items.items()}
    return value.decode() if isinstance(value, bytes) else value


def target_fields(entity, locale, items, npcs=None):
    localized = entity.get('locales', {}).get(locale, {})
    result = {field: localized[field] for field in FIELDS if field in localized}
    lines = [dict(line) for line in result.get('objectiveLines', [])]
    indices = {line['index'] for line in lines}
    for index, target in indexed_client_targets(entity):
        if (target.get('kind') == 'faction' and target.get('type') == 'reputation'
                and 'index' in target and type(target.get('id')) is int and target['id'] > 0):
            for line in lines:
                if line.get('index') == index and line.get('type') == 'reputation':
                    line['factionID'] = target['id']
            continue
        if index in indices:
            continue
        if target['kind'] == 'item':
            entities, kind = items, 'item'
        elif target['kind'] == 'npc' and target.get('type') == 'monster':
            entities, kind = npcs or {}, 'monster'
        else:
            continue
        name = entities.get(str(target['id']), {}).get('locales', {}).get(locale, {}).get('name')
        if name:
            lines.append({'index': index, 'type': kind, 'text': name + ': {current}/{required}'})
    if lines:
        result['objectiveLines'] = sorted(lines, key=lambda line: line['index'])
    return result


def source_fields(entity, locale):
    localized = entity.get('locales', {}).get(locale, {})
    metadata = localized.get('translationMetadata', {}).get('fields', {})
    result = {}
    for field in SOURCE_FIELDS:
        value = localized.get(field) if metadata.get(field, {}).get('origin') in ('original', 'community') else None
        if value:
            result[field] = value
    lines = [line for line in localized.get('objectiveLines', [])
             if metadata.get('objectiveLines.' + str(line['index']), {}).get('origin') == 'original']
    if lines:
        result['objectiveLines'] = lines
    return result


def compare_fields(quest_id, locale, expected, actual, populated, report, counts):
    """Compare every applicable owned field, including absent targets and unexpected output."""
    for field in FIELDS:
        case = {'id': int(quest_id), 'locale': locale, 'field': field}
        if field not in populated and field != 'title':
            if actual.get(field) is not None:
                report['failures'].append({**case, 'reason': 'mismatch', 'expected': None,
                                           'actual': actual[field]})
                counts['failed'] += 1
                counts['cases'] += 1
            else:
                report['notApplicable'].append(case)
            continue
        counts['cases'] += 1
        value = expected.get(field)
        if value is None or value == '' or value == []:
            report['missingTarget'].append(case)
            report['failures'].append({**case, 'reason': 'missing target translation'})
            counts['failed'] += 1
        elif actual.get(field) != value:
            report['failures'].append({**case, 'reason': 'mismatch',
                                       'expected': value, 'actual': actual.get(field)})
            counts['failed'] += 1
        else:
            counts['passed'] += 1


def run_matrix():
    catalog = load_catalog(ROOT, 'quests')
    locales = catalog['locales']
    clients = [locale for locale in locales if locale not in catalog['rosettaLocales']]
    quests = {quest_id: entity for quest_id, entity in catalog['catalogs']['quests'].items()
              if entity.get('usageStatus') not in EXCLUDED_QUEST_STATUSES}
    item_ids = {str(target['id']) for entity in quests.values()
                for target in entity.get('clientObjectiveTargets', []) if target['kind'] == 'item'}
    items = load_catalog(ROOT, 'items', ids={'items': item_ids})['catalogs']['items']
    npc_ids = {str(target['id']) for entity in quests.values()
               for target in entity.get('clientObjectiveTargets', []) if target['kind'] == 'npc'}
    npcs = load_catalog(ROOT, 'npcs', ids={'npcs': npc_ids})['catalogs']['npcs']
    lua = LuaRuntime(encoding=None)
    install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
    db = load_database(lua)
    report = {'missingTarget': [], 'missingSource': [], 'notApplicable': [], 'failures': []}
    counts = Counter({'eligible quests': len(quests), 'cases': 0, 'passed': 0, 'failed': 0})
    for quest_id, entity in quests.items():
        populated = set()
        for locale in locales:
            populated.update(target_fields(entity, locale, items, npcs))
        for locale in locales:
            expected = target_fields(entity, locale, items, npcs)
            actual = from_lua(db.GetQuest(db, int(quest_id), locale.encode())) or {}
            compare_fields(quest_id, locale, expected, actual, populated, report, counts)
    counts['missing target fields'] = len(report['missingTarget'])
    counts['missing source fields'] = len(report['missingSource'])
    counts['not applicable fields'] = len(report['notApplicable'])
    counts['failures'] = len(report['failures'])
    report['kind'] = 'quests'
    report['counts'] = dict(counts)
    report['diagnostics'] = summarize_report(report)
    output = ROOT / 'datasources/imports/translation-matrix/quest-fields.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Quest field matrix:', dict(counts))
    return dict(counts)


if __name__ == '__main__':
    sys.exit(1 if run_matrix()['failed'] else 0)
