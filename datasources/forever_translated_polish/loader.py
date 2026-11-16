"""Forever Translated Polish quest text; upstream fingerprints remain review context."""
from pathlib import Path
from datasources.curseforge import download
from datasources.github_community import write_snapshot, fields
from datasources.lua_data import assignments


def normalize(path, text):
    translations, pins = {}, {}
    for key, value in assignments(text, [('P', 'translations'), ('P', 'pins', 'quests')]):
        if len(key) == 3 and key[:2] == ['P', 'translations']:
            translations[key[2]] = value
        elif len(key) == 4 and key[:3] == ['P', 'pins', 'quests']:
            pins[key[3]] = value
    rows = []
    mapping = {'title': 'title', 'description': 'description', 'objectives': 'summary'}
    for entity_id, value in translations.items():
        for row in fields('quests', entity_id, value, mapping):
            source_field = next(key for key, field in mapping.items() if field == row['field'])
            context = pins.get(entity_id, {}).get(source_field)
            if context:
                row['context'] = {'englishFingerprints': context}
                row['flags'].append('upstreamFingerprint:reviewBeforeReuse')
            rows.append(row)
    return rows, []


SPEC = {'source': 'foreverTranslatedPolish', 'locale': 'plPL', 'origin': 'community',
        'projectID': 1735702, 'archivePattern': r'ForeverTranslations-plPL-(\d+\.\d+\.\d+)\.zip',
        'preserveArchiveRoot': True, 'files': ['ForeverTranslations_plPL/Data[0-9][0-9].lua'],
        'normalize': normalize, 'notice': Path(__file__).with_name('SOURCE.md')}


def fetch(output, pin=None):
    return write_snapshot(SPEC, output, *download(SPEC, pin))
