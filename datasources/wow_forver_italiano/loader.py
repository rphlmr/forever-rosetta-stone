"""Italian beta translations with exact-English guards, including declared AI-authored work."""
from pathlib import Path
import re
from datasources.github_community import fetch as collect, fields
from datasources.lua_data import assignments

TARGETS = {'items': ('items', 'name'), 'itemDescriptionOverrides': ('items', 'description'),
           'spells': ('spells', 'name'), 'spellDescriptionOverrides': ('spells', 'description'),
           'spellAuraDescriptionOverrides': ('spells', 'auraDescription'), 'npcs': ('npcs', 'name'),
           'quests': ('quests', None)}


def normalize(path, text):
    rows = []
    targets = set(re.findall(r'ns\.data\.([A-Za-z_]+)', text)) & TARGETS.keys()
    typed = next(iter(targets)) if len(targets) == 1 else None
    roots = [('ns', 'data', key) for key in TARGETS] + [(key,) for key in ('records', 'overrides', 'spells', 'items', 'quests', 'npcs')]
    for key, table in assignments(text, roots):
        target = key[2] if len(key) >= 3 and key[:2] == ['ns', 'data'] else typed
        if target not in TARGETS or not isinstance(table, dict):
            continue
        entries = table.items() if len(key) in (1, 3) else [(key[3], table)] if len(key) == 4 else []
        kind, field = TARGETS[target]
        for identifier, value in entries:
            if not isinstance(value, dict):
                continue
            if target == 'quests':
                mapping = {'title': 'title', 'description': 'description', 'objectives': 'summary'}
                english = {'title': value.get('enTitle'), 'description': value.get('enDescription'), 'summary': value.get('enObjectives')}
            else:
                mapping = {'name': 'name'} if field == 'name' else {'description': field}
                english = {field: value.get('enDescription') if field == 'description' and kind == 'items' else value.get('en')}
            for row in fields(kind, identifier, value, mapping, english=english):
                row['context'] = {'gameFlavor': 'Forever beta', 'clientBuild': '1.60.1.70009'}
                rows.append(row)
    # Explicit DB2 class records use array positions, with the real entity ID in each record.
    if 'ChrClasses' in path:
        for key, table in assignments(text, [('records',)]):
            if key == ['records'] and isinstance(table, dict):
                for value in table.values():
                    if isinstance(value, dict) and value.get('field') in ('ChrClasses.Name_lang', 'ChrClasses.Name_male_lang'):
                        rows.extend(fields('classes', value.get('id'), value, {'it': 'name'}, english={'name': value.get('en')}))
    return rows, []


SPEC = {'source': 'wowForverItaliano', 'locale': 'itIT', 'origin': 'ai', 'repository': 'z4mbo/WOW-Forver-Italiano',
        'files': ['Addon/Data/*.lua'], 'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return collect(SPEC, output, pin)
