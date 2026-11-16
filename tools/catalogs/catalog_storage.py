"""Read self-contained entity files as catalog documents."""

import copy
import hashlib
import json
import re
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


CATALOGS = ('quests', 'items', 'npcs', 'areas', 'spells', 'talents', 'factions', 'creaturetypes', 'classes', 'races', 'globalstrings', 'professioncategories', 'activities', 'taxinodes', 'books', 'bookpages', 'totemcategories', 'shapeshiftforms', 'itemlimitcategories', 'holidaynames', 'locktypes', 'itemsubclasses', 'gossipoptions', 'sharedstrings')
KINDS = CATALOGS + ('maps',)


def canonical_locale(locale):
    if locale == 'enGB':
        raise ValueError('English is stored as enUS; enGB is not supported')

    return locale


def canonical_locales(locales):
    return list(dict.fromkeys(locale for locale in locales if locale != 'enGB'))


def parse_json(text, source='JSON input'):
    """Parse JSON without silently discarding duplicate object keys."""
    def unique_object(pairs):
        result = {}

        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate JSON key {key!r} in {source}')

            result[key] = value

        return result

    return json.loads(text, object_pairs_hook=unique_object)


def read_json(path):
    """Read a JSON file while rejecting duplicate object keys."""
    return parse_json(Path(path).read_bytes(), path)


def dump_json(value):
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n'


def get_digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def get_catalog_name(kind):
    if kind not in KINDS:
        raise ValueError('Unknown catalog kind: ' + str(kind))

    return 'areas' if kind == 'maps' else kind


def get_entity_path(root, kind, entity_id):
    get_catalog_name(kind)
    entity_id = str(entity_id)

    if not re.fullmatch(r'[1-9][0-9]*', entity_id):
        raise ValueError('Expected positive decimal entity ID: ' + entity_id)

    return Path(root) / 'catalogs' / kind / (entity_id + '.json')


def read_manifest(root, catalog):
    if catalog not in CATALOGS:
        raise ValueError('Unknown catalog: ' + str(catalog))

    path = Path(root) / 'catalogs' / catalog / 'metadata.json'

    if catalog in ('books', 'bookpages', 'totemcategories', 'taxinodes') and not path.exists():
        return {'storageVersion': 2, 'kinds': [catalog], 'document': {'schemaVersion': 1}}
    manifest = read_json(path)

    if manifest.get('storageVersion') != 2:
        raise ValueError('Expected catalog storageVersion 2: ' + str(path))

    expected = ['areas', 'maps'] if catalog == 'areas' else [catalog]

    if sorted(manifest['kinds']) != expected:
        raise ValueError('Unexpected catalog kinds: ' + str(path))

    return manifest


def load_entity(root, kind, entity_id):
    path = get_entity_path(root, kind, entity_id)

    if not path.exists():
        return None

    return read_json(path)


def load_catalog(root, catalog, ids=None):
    """Load all records, or only a kind-to-ID selection; an empty selection reads metadata only."""
    manifest = read_manifest(root, catalog)

    document = copy.deepcopy(manifest['document'])
    document['catalogs'] = {}

    for kind in manifest['kinds']:
        if ids is None:
            paths = sorted((Path(root) / 'catalogs' / kind).glob('*.json'))
            paths = [path for path in paths if path.name != 'metadata.json']
        else:
            paths = [get_entity_path(root, kind, entity_id) for entity_id in (ids.get(kind, []) if ids else [])]

        rows = {}

        for path in paths:
            get_entity_path(root, kind, path.stem)

            if path.exists():
                rows[path.stem] = read_json(path)

        document['catalogs'][kind] = rows

    return document


def load_catalogs(root, scope=None):
    return {catalog: load_catalog(root, catalog, scope) for catalog in CATALOGS}
