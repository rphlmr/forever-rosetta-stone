"""WoWLang quest context for supported Polish, Turkish and Ukrainian target locales."""
from pathlib import Path
from datasources.github_community import fetch as collect
from datasources.quest_translator import normalize as normalize_quests


def normalize(path, text):
    prefix = path.split('/')[0]
    locale = {'WoWPL': 'plPL', 'WoWTR': 'trTR', 'WoWUA': 'ukUA'}.get(prefix)
    return normalize_quests(text, locale) if locale else ([], [])


SPEC = {'source': 'wowLang', 'locales': ['plPL', 'trTR', 'ukUA'], 'origin': 'community',
        'repository': 'DiNaSoR/WoWLang',
        'files': ['WoWPL/Translations/QuestData_PL.lua', 'WoWTR/Translations/QuestData_TR.lua', 'WoWUA/Translations/QuestData_UA.lua'],
        'maxFileBytes': 48 * 1024 * 1024, 'maxTextBytes': 128 * 1024 * 1024,
        'flags': ['licenseDeclarationConflict:contextOnly'], 'normalize': normalize,
        'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return collect(SPEC, output, pin)
