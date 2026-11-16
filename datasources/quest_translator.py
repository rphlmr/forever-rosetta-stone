"""Literal QuestTranslator quest tables shared by community Classic datasets."""
import re
from datasources.github_community import fields
from datasources.lua_data import assignments


def normalize(text, locale=None):
    rows = []
    for key, table in assignments(text, [('QTR_QuestData',), ('QTR_questData',), ('QuestTranslator_QuestData',)], allow_duplicates=True):
        if len(key) != 1 or not isinstance(table, dict):
            continue
        for identifier, value in table.items():
            if not str(identifier).isdecimal() or not isinstance(value, dict):
                continue
            mapping = {'Title': 'title', 'Description': 'description', 'Objectives': 'summary'}
            for row in fields('quests', int(identifier), value, mapping):
                if re.search(r'YOUR_(?:NAME|CLASS|RACE|GENDER)|NEW_LINE', row['text']):
                    row['flags'].append('upstreamPlaceholders:reviewBeforeReuse')
                if locale:
                    row['locale'] = locale
                row['context'] = {'gameFlavor': 'Classic', 'englishContext': 'notProvided'}
                row['flags'].append('crossVersionContext:checkForeverMeaning')
                rows.append(row)
    return rows, []
