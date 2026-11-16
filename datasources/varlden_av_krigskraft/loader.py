"""Världen av Krigskraft's typed ID tables and explicit English spell templates."""
from pathlib import Path
from datasources.curseforge import download
from datasources.github_community import write_snapshot, fields
from datasources.lua_data import assignments


def normalize(path, text):
    rows = []
    mapping = {'quest': ('quests', {'t': 'title', 'd': 'description', 'o': 'summary'}),
               'item': ('items', {'n': 'name', 'd': 'description'}),
               'spell': ('spells', {'n': 'name', 'd': 'description', 'a': 'auraDescription'}),
               'npc': ('npcs', {None: 'name'})}
    for key, value in assignments(text, [('VAK', 'L')]):
        if len(key) != 3 or key[2] not in mapping or not isinstance(value, dict):
            continue
        kind, field_mapping = mapping[key[2]]
        for entity_id, record in value.items():
            english = {field: record[source] for source, field in [('e', 'description'), ('ea', 'auraDescription')]
                       if isinstance(record, dict) and isinstance(record.get(source), str)}
            rows.extend(fields(kind, entity_id, record, field_mapping, english=english))
    return rows, []


SPEC = {'source': 'varldenAvKrigskraft', 'locale': 'svSE', 'origin': 'ai',
        'projectID': 1734807, 'archivePattern': r'VarldenAvKrigskraft-(\d+\.\d+\.\d+)\.zip',
        'files': ['Data/Quest.lua', 'Data/Item.lua', 'Data/Spell.lua', 'Data/Npc.lua'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return write_snapshot(SPEC, output, *download(SPEC, pin))
