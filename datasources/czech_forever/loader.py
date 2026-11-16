"""Czech Forever CurseForge release: typed quest fields, NPC IDs and English name pairs."""
from pathlib import Path
from datasources.github_community import write_snapshot, fields
from datasources.curseforge import download
from datasources.lua_data import assignments


def normalize(path, text):
    rows, lookups = [], []
    if '/Quests' in path:
        for key, value in assignments(text, [('d',)]):
            if len(key) == 2:
                rows.extend(fields('quests', key[1], value, {'t': 'title', 'a': 'description', 'o': 'summary'}))
    elif path.endswith('/Npcs.lua'):
        for key, value in assignments(text, [('n',)]):
            if len(key) == 2:
                rows.extend(fields('npcs', key[1], value, {None: 'name'}))
    elif path.endswith('/Names.lua'):
        for key, value in assignments(text, [('n',)]):
            if len(key) != 2 or key[1] not in ('item', 'spell', 'both') or not isinstance(value, str):
                continue
            for line in value.splitlines():
                english, separator, translated = line.partition('\t')
                if separator and english and translated:
                    lookups.append({'kinds': ['items', 'spells'] if key[1] == 'both' else [key[1] + 's'],
                                    'fields': ['name'], 'key': english, 'algorithm': 'exact', 'text': translated})
    return rows, lookups


SPEC = {'source': 'czechForever', 'locale': 'csCZ', 'origin': 'community', 'projectID': 1732355,
        'archivePattern': r'CzechForever-(\d+\.\d+\.\d+)\.zip',
        'files': ['Data/Quests*.lua', 'Data/Npcs.lua', 'Data/Names.lua'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    if output.exists():
        raise ValueError('Use a new community snapshot directory')
    return write_snapshot(SPEC, output, *download(SPEC, pin))
