"""Classic Italian quest text by Icedany and WoWita contributors, without executing the addon."""
from pathlib import Path
from datasources.github_community import fetch as collect
from datasources.quest_translator import normalize as normalize_quests


def normalize(path, text):
    return normalize_quests(text)


SPEC = {'source': 'wowitaQuests', 'locale': 'itIT', 'origin': 'community',
        'repository': 'deemonder/WoWita-quests', 'files': ['QuestData_it.lua'],
        'flags': ['licenseNotSpecified:contextOnly'], 'normalize': normalize,
        'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return collect(SPEC, output, pin)
