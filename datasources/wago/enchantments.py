"""Prepare a source-owned item enchantment catalog from verified Forever exports."""

import csv
from contextlib import closing
import hashlib
import json
from pathlib import Path

from datasources.corpus.translation_corpus import open_corpus
from tools.catalogs.catalog_storage import dump_json, get_entity_path, read_json
from tools.catalogs.import_policy import verify_sources
from tools.catalogs.official_text import OFFICIAL_LOCALES, source_build


KIND = 'itemenchantments'
TABLE = 'SpellItemEnchantment'
FIELDS = {'Name_lang': 'name', 'HordeName_lang': 'nameHorde'}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_exports(root, database):
    with closing(open_corpus(database)) as db:
        inputs = {row['path']: row['sha256'] for row in db.execute('SELECT path,sha256 FROM inputs')}

    snapshots = []
    for name in sorted(inputs):
        if not name.endswith('/wago/manifest.json'):
            continue
        path = root / name
        manifest = read_json(path)
        rows = [row for row in manifest['results'] if row['table'] == TABLE
                and row['status'] in ('downloaded', 'existing') and row['locale'] in OFFICIAL_LOCALES]
        if {row['locale'] for row in rows} != OFFICIAL_LOCALES or len(rows) != len(OFFICIAL_LOCALES):
            continue
        build = manifest['build']
        version = source_build({'sourceBuild': build})
        if version is None or version[0] != 1 or version[1] < 60:
            continue
        snapshots.append((version, build, path.parent, rows))

    if len(snapshots) != 1:
        raise ValueError(f'Expected one complete Forever {TABLE} snapshot (found {len(snapshots)})')

    _, build, directory, rows = snapshots[0]
    exports, checksums = {}, {}
    for row in rows:
        path = (directory / row['file']).resolve()
        if not path.is_relative_to(directory) or str(path.relative_to(root)) not in inputs:
            raise ValueError(f'Invalid enchantment export path: {path}')
        checksum = digest(path.read_bytes())
        if checksum != row['sha256'] or checksum != inputs[str(path.relative_to(root))]:
            raise ValueError(f'Enchantment export checksum changed: {path}')
        checksums[str(path.relative_to(root))] = checksum
        with path.open(encoding='utf-8-sig', newline='') as stream:
            reader = csv.DictReader(stream)
            if not {'ID', 'Duration', *FIELDS}.issubset(reader.fieldnames or ()):
                raise ValueError(f'Missing enchantment columns: {path}')
            records = {}
            for record in reader:
                entity_id = int(record['ID'])
                if entity_id <= 0 or entity_id in records or int(record['Duration']) < 0:
                    raise ValueError(f'Invalid or duplicate enchantment {entity_id}: {path}')
                records[entity_id] = record
            if not records or len(records) != row['rows']:
                raise ValueError(f'Enchantment export row count mismatch: {path}')
            exports[row['locale']] = records

    english = exports['enUS']
    for locale, records in exports.items():
        if records.keys() != english.keys() or any(records[key]['Duration'] != value['Duration']
                                                   for key, value in english.items()):
            raise ValueError(f'Enchantment structure differs between enUS and {locale}')
    return build, exports, checksums


def prepare(root, database, output):
    root, output = Path(root).resolve(), Path(output).resolve()
    if not output.is_relative_to(root / 'datasources/imports') or output.exists():
        raise ValueError('Use a new output directory under datasources/imports/')
    database = verify_sources(database, root)
    build, exports, checksums = read_exports(root, database)
    output.mkdir(parents=True)
    files = []

    def stage(path, record):
        before = path.read_bytes() if path.exists() else None
        after = dump_json(record).encode()
        if before is not None and json.loads(before) == record:
            return
        result = f'{len(files):05d}.json'
        (output / result).write_bytes(after)
        files.append({'path': str(path.relative_to(root)), 'result': result,
                      'beforeSha256': digest(before) if before is not None else None,
                      'afterSha256': digest(after)})

    catalog = root / 'catalogs' / KIND
    metadata_path = catalog / 'metadata.json'
    metadata = read_json(metadata_path) if metadata_path.exists() else {
        'document': {'schemaVersion': 1}, 'storageVersion': 2, 'kinds': [KIND],
    }
    previous_build = metadata['document'].get('sourceBuild')
    if previous_build and source_build({'sourceBuild': previous_build}) > source_build({'sourceBuild': build}):
        raise ValueError('Cannot refresh enchantments from an older build')
    metadata['document']['sourceBuild'] = build
    stage(metadata_path, metadata)

    named, changed_english = [], []
    for entity_id, english in sorted(exports['enUS'].items()):
        if not english['Name_lang'].strip():
            continue
        named.append(str(entity_id))
        path = get_entity_path(root, KIND, entity_id)
        record = read_json(path) if path.exists() else {'locales': {}}
        old_english = record['locales'].get('enUS', {}).copy()
        record['duration'] = int(english['Duration'])
        for locale, records in exports.items():
            for column, field in FIELDS.items():
                value = records[entity_id][column]
                if not value.strip() or not english[column].strip():
                    continue
                target = record['locales'].setdefault(locale, {})
                fields = target.setdefault('translationMetadata', {}).setdefault('fields', {})
                current = fields.get(field, {})
                if field in target and current.get('source') != 'wago':
                    continue
                # A localized export can temporarily fall back to English during a build update.
                if (locale != 'enUS' and value == english[column] and field in target
                        and target[field] != old_english.get(field)
                        and target[field] != value):
                    continue
                if target.get(field) == value and current.get('origin') == 'original':
                    continue
                if locale == 'enUS' and field in target:
                    changed_english.append({'id': entity_id, 'field': field, 'before': target[field], 'after': value})
                target[field] = value
                fields[field] = {'origin': 'original', 'source': 'wago',
                                 'sourceLocale': locale, 'sourceBuild': build}
        stage(path, record)

    manifest = {'database': str(database), 'databaseSha256': digest(database.read_bytes()),
                'policyInputs': checksums, 'files': files, 'sourceBuild': build,
                'namedEnchantments': len(named)}
    (output / 'manifest.json').write_text(dump_json(manifest))
    (output / 'translation-scope.json').write_text(dump_json({KIND: named}))
    (output / 'changed-english.json').write_text(dump_json(changed_english))
    return {'sourceBuild': build, 'namedEnchantments': len(named), 'changedFiles': len(files)}
