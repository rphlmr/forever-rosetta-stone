"""PolishForever quests use entity IDs; other tables use English-text hashes, not entity IDs."""
from pathlib import Path
from datasources.github_community import fetch as collect, fields
from datasources.lua_data import assignments


def normalize(path, text):
    rows, lookups = [], []
    roots = [('PF', 'Quests'), *[('PF', 'Text', key) for key in ('Items', 'Spells', 'Creatures', 'Places')]]
    for key, table in assignments(text, roots):
        if not isinstance(table, dict):
            continue
        if key == ['PF', 'Quests']:
            for entity_id, value in table.items():
                rows.extend(fields('quests', entity_id, value, {1: 'title', 2: 'summary', 3: 'description'}))
        elif key[-1] in ('Items', 'Spells', 'Creatures', 'Places'):
            kinds = {'Items': ['items'], 'Spells': ['spells'], 'Creatures': ['npcs'], 'Places': ['areas', 'maps']}
            for hashed, value in table.items():
                if type(hashed) is int and isinstance(value, str) and value.strip():
                    lookups.append({'kinds': kinds[key[-1]], 'fields': ['name', 'description', 'auraDescription']
                                    if key[-1] in ('Items', 'Spells') else ['name'], 'key': hashed,
                                    'algorithm': 'polish-hash', 'text': value})
    return rows, lookups


SPEC = {'source': 'polishForever', 'locale': 'plPL', 'origin': 'ai', 'repository': 'JSlomian/PolishForever',
        'files': ['Data/Quests.lua', 'Data/Items.lua', 'Data/Spells.lua', 'Data/Creatures.lua', 'Data/Places.lua'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return collect(SPEC, output, pin)
