"""ForeverTR numeric quest, item and NPC IDs; hash-keyed spell tables are excluded."""
from pathlib import Path
from datasources.curseforge import download
from datasources.github_community import write_snapshot, fields
from datasources.lua_data import assignments


def normalize(path, text):
    rows = []
    mapping = {'Q': ('quests', {'t': 'title', 'd': 'description', 'o': 'summary'}),
               'I': ('items', {'n': 'name'}), 'N': ('npcs', {'n': 'name'})}
    for key, value in assignments(text, [('D',)]):
        if len(key) == 3 and key[1] in mapping:
            kind, field_mapping = mapping[key[1]]
            rows.extend(fields(kind, key[2], value, field_mapping))
    return rows, []


SPEC = {'source': 'foreverTR', 'locale': 'trTR', 'origin': 'ai',
        'projectID': 1741399, 'archivePattern': r'ForeverTR-(\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?)\.zip',
        'files': ['Data/Quests_*.lua', 'Data/Items.lua', 'Data/NPCs.lua'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return write_snapshot(SPEC, output, *download(SPEC, pin))
