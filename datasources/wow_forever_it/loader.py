"""Italian Forever/QuestIT context; upstream fingerprints and translation attribution are retained."""
from pathlib import Path
from datasources.github_community import fetch as collect, fields
from datasources.lua_data import assignments

QUEST_FIELDS = {'title': 'title', 'text': 'description', 'objectives': 'summary'}


def quest_rows(identifier, table, path):
    rows = []
    if not isinstance(table, dict):
        return rows
    for upstream, value in table.items():
        field = QUEST_FIELDS.get(str(upstream).split('#')[0])
        if field is None or not isinstance(value, dict) or not isinstance(value.get('it'), str):
            continue
        for row in fields('quests', identifier, value, {'it': field}):
            hashes = value.get('enHash')
            row['context'] = {'upstreamField': str(upstream), 'englishFingerprints': hashes,
                              'gameFlavor': 'Classic' if value.get('vanilla') else 'Forever',
                              'attribution': 'QuestIT / Drakanast / QuestIT Discord / #italyforazeroth'}
            if hashes:
                row['flags'].append('upstreamFingerprint:reviewBeforeReuse')
            if value.get('vanilla'):
                row['flags'].append('crossVersionContext:checkForeverMeaning')
            rows.append(row)
    return rows


def normalize(path, text):
    rows, lookups = [], []
    roots = [('WoWForeverIT_QuestIT', 'DataIT'), ('db',), ('WoWForeverIT_Items',),
             ('WoWForeverIT_ItemDescriptions',), ('WoWForeverIT_Creatures',), ('WoWForeverIT_Spells',)]
    for key, table in assignments(text, roots):
        if key == ['WoWForeverIT_QuestIT', 'DataIT'] and isinstance(table, dict):
            for identifier, value in table.items():
                rows.extend(quest_rows(identifier, value, path))
        elif key[0] == 'db':
            if len(key) == 2:
                rows.extend(quest_rows(key[1], table, path))
            elif len(key) == 3:
                rows.extend(quest_rows(key[1], {key[2]: table}, path))
        elif key[0] in ('WoWForeverIT_Items', 'WoWForeverIT_ItemDescriptions', 'WoWForeverIT_Creatures'):
            kind = 'npcs' if key[0] == 'WoWForeverIT_Creatures' else 'items'
            field = 'description' if key[0] == 'WoWForeverIT_ItemDescriptions' else 'name'
            records = table.items() if len(key) == 1 and isinstance(table, dict) else [(key[1], table)] if len(key) == 2 else []
            for identifier, value in records:
                if not isinstance(value, dict):
                    continue
                origin = 'ai' if 'Imported' in path or 'z4mbo' in text[:200] else None
                rows.extend(fields(kind, identifier, value, {'it': field}, origin, {field: value.get('en')}))
        elif key == ['WoWForeverIT_Spells'] and isinstance(table, dict):
            for english, value in table.items():
                if isinstance(english, str) and isinstance(value, str):
                    lookups.append({'kinds': ['spells'], 'fields': ['name'], 'algorithm': 'exact', 'key': english, 'text': value})
    return rows, lookups


SPEC = {'source': 'wowForeverIT', 'locale': 'itIT', 'origin': 'community', 'repository': 'polletto/WoWForeverIT',
        'files': ['WoWForeverIT/Vendor/QuestIT/Data_it.lua', 'WoWForeverIT/Locales/*.lua'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return collect(SPEC, output, pin)
