"""Turkish Vanilla/OctoWOW quest context from the public QuestTranslator fork."""
from pathlib import Path
from datasources.github_community import fetch as collect
from datasources.quest_translator import normalize as normalize_quests


def normalize(path, text):
    rows, lookups = normalize_quests(text)
    for row in rows:
        row['context']['gameFlavor'] = 'Vanilla / OctoWOW'
    return rows, lookups


SPEC = {'source': 'questTranslatorTR', 'locale': 'trTR', 'origin': 'community',
        'repository': 'devteabct78/questtranslator-vanilla-turkish', 'files': ['QuestData_it.lua'],
        'flags': ['licenseNotSpecified:contextOnly', 'crossServerContext:checkForeverMeaning'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return collect(SPEC, output, pin)
