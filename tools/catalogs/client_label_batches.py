"""Snapshot disjoint readable-label jobs and guard agent results before applying patches."""

import difflib
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/python'))
from catalog_placeholder_matrix import signature
from tools.catalogs.catalog_storage import dump_json, get_entity_path, load_catalog, read_json

def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def prepare(root, locale, output, batch_size=60, eligible=None):
    entities = load_catalog(root, 'globalstrings')['catalogs']['globalstrings']
    if eligible is not None:
        from tools.build.client_label_scope import tooltip_globalstring_keys
        used = tooltip_globalstring_keys(root, {entity['key'] for entity in entities.values()})
        entities = {entity_id: entity for entity_id, entity in entities.items() if entity['key'] in used}
    ids = {entity['key']: id for id, entity in entities.items()}
    english = {entity['key']: entity['locales'].get('enUS', {}).get('name') for entity in entities.values()}
    target = {entity['key']: entity['locales'].get(locale, {}).get('name') for entity in entities.values()}
    keys = [key for key, value in target.items() if value is None and english.get(key)]
    if eligible is not None:
        keys = [key for key in keys if eligible(ids[key], english[key])]
    prefixes = ('PROFESSIONS_', 'CHARACTER_PROFESSION_', 'ITEM_', 'SPELL_', 'TOOLTIP_',
                'TRADE_SKILL_', 'SKILL_', 'REAGENT', 'CRAFT_', 'ENCHANT_')
    keys.sort(key=lambda key: (not key.startswith(prefixes), key))
    output.mkdir(parents=True, exist_ok=True)
    manifest = []
    for index, offset in enumerate(range(0, len(keys), batch_size)):
        selected = keys[offset:offset + batch_size]
        records = {key: {'id': ids[key], 'source': english[key], 'before': target[key]} for key in selected}
        batch = {'locale': locale, 'records': records, 'snapshotHash': digest(records)}
        stem = f'{index:05d}'
        batch_path, result_path = output / (stem + '.batch.json'), output / (stem + '.results.json')
        if batch_path.exists() or result_path.exists():
            raise ValueError('Refusing to overwrite prepared assignments')
        batch_path.write_text(json.dumps(batch, ensure_ascii=False, indent=2) + '\n')
        result_path.write_text(json.dumps({key: None for key in selected}, ensure_ascii=False, indent=2) + '\n')
        manifest.append({'batch': batch_path.name, 'results': result_path.name, 'keys': len(selected)})
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def validate(root, batch, results):
    if digest(batch['records']) != batch['snapshotHash']:
        raise ValueError('Changed assignment snapshot')
    if set(results) != set(batch['records']):
        raise ValueError('Results must contain exactly the assigned keys')
    locale = batch['locale']
    for key, entry in batch['records'].items():
        entity = read_json(get_entity_path(root, 'globalstrings', entry['id']))
        if (entity.get('key') != key or entity['locales'].get('enUS', {}).get('name') != entry['source']
                or entity['locales'].get(locale, {}).get('name') != entry['before']):
            raise ValueError('Stale source/target label: ' + key)
        value = results[key]
        if not isinstance(value, str) or not value.strip():
            raise ValueError('Missing translation: ' + key)
        if signature(entry['source'], 'items') != signature(value, 'items'):
            raise ValueError('Changed placeholders or markup: ' + key)
    return locale


def patch(root, batch, results):
    locale = validate(root, batch, results)
    patches = ['*** Begin Patch\n']
    for key, value in results.items():
        path = get_entity_path(root, 'globalstrings', batch['records'][key]['id'])
        before = path.read_text()
        entity = read_json(path)
        target = entity['locales'].setdefault(locale, {})
        target['name'] = value
        target.setdefault('translationMetadata', {}).setdefault('fields', {})['name'] = {
            'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}
        difference = list(difflib.unified_diff(before.splitlines(True), dump_json(entity).splitlines(True), n=3))[2:]
        patches.append('*** Update File: ' + str(path) + '\n')
        patches.extend('@@\n' if line.startswith('@@') else line for line in difference)
    patches.append('*** End Patch\n')
    return ''.join(patches)
