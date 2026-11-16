"""Ukrainian ClassicUA: Classic data with Forever overlays and per-entry AI markings."""
from pathlib import Path
from datasources.github_community import fetch as collect, fields
from datasources.lua_data import assignments


def normalize(path, text):
    rows = []
    roots = [('quest_alliance',), ('quest_both',), ('quest_horde',), ('items',), ('npc',), ('spells',)]
    for key, table in assignments(text, roots):
        if len(key) != 1 or not isinstance(table, dict):
            continue
        quest = key[0].startswith('quest_')
        kind = 'quests' if quest else {'items': 'items', 'npc': 'npcs', 'spells': 'spells'}[key[0]]
        for entity_id, value in table.items():
            if isinstance(value, dict):
                rows.extend(fields(kind, entity_id, value, {1: 'title', 2: 'description', 3: 'summary'} if quest else {1: 'name'},
                                   'ai' if value.get('ai') else 'community', {'title' if quest else 'name': value.get('en')}))
    return rows, []


SPEC = {'source': 'classicUA', 'locale': 'ukUA', 'origin': 'community', 'repository': 'greenya/ClassicUA',
        'files': ['entries/classic/quest_*.lua', 'entries/forever/quest_*.lua', 'entries/classic/item.lua',
                  'entries/forever/item.lua', 'entries/classic/npc.lua', 'entries/forever/npc.lua',
                  'entries/classic/spell*.lua', 'entries/forever/spell*.lua'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return collect(SPEC, output, pin)
