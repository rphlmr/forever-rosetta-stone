"""Prepare isolated catalog assignments and validate agent results before generating patches."""

import argparse
from difflib import unified_diff
from functools import partial
import hashlib
import json
import re
import runpy
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.catalogs.catalog_storage import (KINDS, canonical_locales, dump_json, get_catalog_name,
                             get_entity_path, load_catalog, read_json)
from tools.build.runtime_catalog import get_has_ai_translation, get_tooltip_source_text
from tools.catalogs.official_text import OFFICIAL_LOCALES, TEXT_FIELDS
from tools.catalogs.english_scope import has_english_text


ROOT = Path(__file__).resolve().parents[2]
TOKEN_TOOLS = runpy.run_path(str(Path(__file__).with_name('translation-work.py')))
GET_TOKENS = TOKEN_TOOLS['get_tokens']
GET_ENCHANTMENT_TOKENS = TOKEN_TOOLS['get_enchantment_tokens']
GET_QUEST_TOKENS = TOKEN_TOOLS['get_quest_tokens']
GET_DIALOGUE_TOKENS = partial(GET_QUEST_TOKENS, allow_sentence_selectors=True)
GET_BOOK_TOKENS = TOKEN_TOOLS['get_book_tokens']


def get_digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def get_scope_pairs(scope):
    """Validate an explicit assignment and return stable, unique entity identities."""
    if not isinstance(scope, dict) or not scope or set(scope) - set(KINDS):
        raise ValueError('Scope must map supported entity kinds to nonempty ID lists')

    pairs = []

    for kind in sorted(scope):
        ids = scope[kind]

        if not isinstance(ids, list) or not ids:
            raise ValueError('Expected nonempty ID list for ' + kind)

        if any(not isinstance(entity_id, str) or not re.fullmatch(r'[1-9][0-9]*', entity_id) for entity_id in ids):
            raise ValueError('Expected positive decimal string IDs for ' + kind)

        if len(ids) != len(set(ids)):
            raise ValueError('Duplicate entity IDs in scope: ' + kind)

        pairs.extend((kind, entity_id) for entity_id in sorted(ids, key=int))

    return pairs


def get_locale_config(root):
    metadata = load_catalog(root, 'quests', ids={'quests': []})
    metadata['locales'] = canonical_locales(metadata['locales'])
    return {key: metadata[key] for key in ('locales', 'rosettaLocales') if key in metadata}


def load_selected_records(root, pairs):
    selections = {}

    for kind, entity_id in pairs:
        selections.setdefault(get_catalog_name(kind), {}).setdefault(kind, []).append(entity_id)

    records = {}

    for catalog, selection in selections.items():
        records.update(load_catalog(root, catalog, ids=selection)['catalogs'])

    return records


def prepare_batches(root, scope, batch_size):
    """Snapshot each assigned entity once; an absent record is an explicit new-record assignment."""
    if batch_size < 1:
        raise ValueError('Batch size must be positive')

    pairs = get_scope_pairs(scope)
    config = get_locale_config(root)
    selected = load_selected_records(root, pairs)
    batches = []

    for offset in range(0, len(pairs), batch_size):
        records = {}
        snapshots = {}

        for kind, entity_id in pairs[offset:offset + batch_size]:
            record = selected[kind].get(entity_id)
            records.setdefault(kind, {})[entity_id] = record
            snapshots.setdefault(kind, {})[entity_id] = get_digest(record)

        batch = {'schemaVersion': 1, 'localeConfig': config, 'records': records, 'snapshots': snapshots}
        batches.append({**batch, 'batchHash': get_digest(batch)})

    return batches


def get_text_fields(localized):
    fields = {key: localized[key] for key in TEXT_FIELDS if key in localized}
    seen = set()

    for line in localized.get('objectiveLines', []):
        index = line.get('index')

        if not isinstance(index, int) or isinstance(index, bool) or index < 1 or index in seen:
            raise ValueError('Objective lines require unique positive integer indices')

        seen.add(index)
        fields['objectiveLines.' + str(index)] = line.get('text')

    return fields


def validate_record(kind, entity_id, before, after, locales):
    """Check field origins, changed AI placeholders, and coverage of new or changed English text."""
    if not isinstance(after, dict) or not isinstance(after.get('locales'), dict):
        raise ValueError('Expected a localized entity: ' + kind + '/' + entity_id)

    if before is None and not after['locales']:
        raise ValueError('Expected a nonempty new localized entity: ' + kind + '/' + entity_id)

    if set(after['locales']) - set(locales):
        raise ValueError('Unsupported locale in ' + kind + '/' + entity_id)

    prior_locales = (before or {}).get('locales', {})

    if any(not isinstance(localized, dict) for localized in after['locales'].values()):
        raise ValueError('Expected localized field objects: ' + kind + '/' + entity_id)

    after_fields = {locale: get_text_fields(localized) for locale, localized in after['locales'].items()}
    before_fields = {locale: get_text_fields(localized) for locale, localized in prior_locales.items()}

    for locale, fields in before_fields.items():
        if set(fields) - set(after_fields.get(locale, {})):
            raise ValueError('Batch results must preserve existing text fields: ' + kind + '/' + entity_id + '/' + locale)

    for locale, localized in after['locales'].items():
        get_has_ai_translation(kind, entity_id, locale, localized)
        metadata = localized.get('translationMetadata', {}).get('fields', {})

        for field, text in after_fields[locale].items():
            unchanged = text == before_fields.get(locale, {}).get(field)

            blank_separator = (kind == 'globalstrings' and field == 'name'
                               and after.get('key') == 'LARGE_NUMBER_SEPERATOR'
                               and text in ('', ' ', '\u00a0', '\u202f'))
            if not isinstance(text, str) or (not text.strip() and not unchanged and not blank_separator):
                raise ValueError('Expected nonempty text: ' + kind + '/' + entity_id + '/' + locale + '/' + field)

            origin = metadata.get(field, {}).get('origin')

            if origin not in ('original', 'community', 'ai'):
                raise ValueError('Missing field origin: ' + kind + '/' + entity_id + '/' + locale + '/' + field)
            if locale == 'enUS' and not unchanged and origin == 'ai' \
                    and field not in before_fields.get('enUS', {}):
                raise ValueError('An English source must not be invented by translation: ' + field)
            if locale != 'enUS' and not unchanged and not field.startswith('objectiveLines.') \
                    and not has_english_text(after, field):
                raise ValueError('Text without an English source is outside catalog scope: ' + field)

            prior_origin = prior_locales.get(locale, {}).get('translationMetadata', {}).get('fields', {}).get(field, {}).get('origin')
            if prior_origin == 'original' and origin != 'original':
                raise ValueError('Official wording must not be replaced by an authored translation: ' + field)
            if prior_origin == 'community' and origin == 'ai':
                raise ValueError('Community source wording must not be replaced by an authored translation: ' + field)
            if unchanged or origin != 'ai':
                continue

            source_locale = metadata[field].get('sourceLocale')
            source = after_fields.get(source_locale, {}).get(field)

            if source is None and kind in ('items', 'spells') and field in ('description', 'auraDescription', 'setName'):
                source = get_tooltip_source_text(after, source_locale, field)

            if source is None:
                raise ValueError('Changed AI text requires its source field and locale: ' + field)

            getter = (GET_DIALOGUE_TOKENS if field.startswith('dialogue.') else
                      GET_BOOK_TOKENS if kind in ('books', 'bookpages') else
                      GET_QUEST_TOKENS if kind == 'quests' else
                      GET_ENCHANTMENT_TOKENS if kind == 'itemenchantments' else GET_TOKENS)
            if getter(text) != getter(source):
                raise ValueError('Placeholder mismatch: ' + kind + '/' + entity_id + '/' + locale + '/' + field)

    changed_source_fields = {
        field for field, text in after_fields.get('enUS', {}).items()
        if text != before_fields.get('enUS', {}).get(field)
    }

    if before is None:
        changed_source_fields.update(field for fields in after_fields.values() for field in fields)

    for field in changed_source_fields:
        missing = [locale for locale in locales if field not in after_fields.get(locale, {})]

        if missing:
            raise ValueError('Changed English field lacks locale coverage: ' + field + ': ' + ', '.join(missing))


def validate_batch(root, batch, results):
    """Reject altered assignments, stale records, or submissions outside the exact assigned scope."""
    payload = {key: value for key, value in batch.items() if key != 'batchHash'}

    if batch.get('schemaVersion') != 1 or batch.get('batchHash') != get_digest(payload):
        raise ValueError('Batch snapshot changed; prepare a fresh assignment')

    records = batch['records']
    expected_scope = {kind: list(rows) for kind, rows in records.items()}
    pairs = get_scope_pairs(expected_scope)

    if not isinstance(results, dict) or set(results) != set(records):
        raise ValueError('Result kinds must match the assigned scope exactly')

    for kind, rows in records.items():
        if not isinstance(results[kind], dict) or set(results[kind]) != set(rows):
            raise ValueError('Result IDs must match the assigned scope exactly: ' + kind)

    if batch['localeConfig'] != get_locale_config(root):
        raise ValueError('Supported locale configuration changed; prepare a fresh assignment')

    current = load_selected_records(root, pairs)

    for kind, entity_id in pairs:
        before = records[kind][entity_id]
        snapshot = batch['snapshots'][kind][entity_id]

        if get_digest(before) != snapshot or get_digest(current[kind].get(entity_id)) != snapshot:
            raise ValueError('Catalog record changed: ' + kind + '/' + entity_id)

        validate_record(kind, entity_id, before, results[kind][entity_id], batch['localeConfig']['locales'])

    return pairs


def create_patch(root, batch, results, *, compact=False):
    """Generate dedicated apply_patch input without writing to maintained catalog files."""
    pairs = validate_batch(root, batch, results)
    blocks = ['*** Begin Patch\n']

    for kind, entity_id in pairs:
        if results[kind][entity_id] == batch['records'][kind][entity_id]:
            continue

        path = get_entity_path(root, kind, entity_id)
        replacement = dump_json(results[kind][entity_id])

        if path.exists():
            original = path.read_text(encoding='utf-8')
            current = json.loads(original)

            if get_digest(current) != batch['snapshots'][kind][entity_id]:
                raise ValueError('Catalog record changed during patch generation: ' + kind + '/' + entity_id)

            blocks.append('*** Update File: ' + str(path) + '\n')
            if compact:
                diff = list(unified_diff(original.splitlines(keepends=True), replacement.splitlines(keepends=True)))
                blocks.extend('@@\n' if line.startswith('@@') else line for line in diff[2:])
                continue
            blocks.append('@@\n')
            blocks.extend('-' + line + '\n' for line in original.splitlines())
        else:
            if batch['records'][kind][entity_id] is not None:
                raise ValueError('Catalog record disappeared during patch generation: ' + kind + '/' + entity_id)

            blocks.append('*** Add File: ' + str(path) + '\n')

        blocks.extend('+' + line + '\n' for line in replacement.splitlines())

    blocks.append('*** End Patch\n')
    return ''.join(blocks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--database', type=Path, help='Verified corpus required for new AI translations.')
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare')
    prepare.add_argument('--scope', type=Path, required=True)
    prepare.add_argument('--output-dir', type=Path, required=True)
    prepare.add_argument('--batch-size', type=int, default=25)
    prepare_labels = commands.add_parser('prepare-labels')
    prepare_labels.add_argument('--locale', required=True)
    prepare_labels.add_argument('--output-dir', type=Path, required=True)
    prepare_labels.add_argument('--batch-size', type=int, default=60)
    for label_command in ('check-labels', 'patch-labels'):
        command = commands.add_parser(label_command)
        command.add_argument('--batch', type=Path, required=True)
        command.add_argument('--results', type=Path, required=True)
        if label_command == 'patch-labels': command.add_argument('--output', type=Path, required=True)

    for name in ('check', 'patch', 'patch-dialogue'):
        command = commands.add_parser(name)
        command.add_argument('--batch', type=Path, required=True)
        command.add_argument('--results', type=Path, required=True)

        if name in ('patch', 'patch-dialogue'):
            command.add_argument('--output', type=Path, required=True)

    args = parser.parse_args()

    if args.command in ('prepare-labels', 'check-labels', 'patch-labels'):
        from tools.catalogs import client_label_batches as labels
        from tools.catalogs.import_policy import OfficialEvidence, ai_block_reason
        evidence = OfficialEvidence(args.database, args.root) if args.database else None
        if args.command == 'prepare-labels':
            if args.locale not in get_locale_config(args.root)['locales']:
                parser.error('Unsupported target locale')
            if args.batch_size < 1: parser.error('Batch size must be positive')
            jobs = labels.prepare(args.root, args.locale, args.output_dir, args.batch_size,
                eligible=lambda entity_id, english: ai_block_reason(args.locale, 'globalstrings', entity_id,
                                                                    'name', english, evidence) is None)
            print(f'Prepared {len(jobs)} disjoint client-label batches')
        else:
            batch, results = read_json(args.batch), read_json(args.results)
            labels.validate(args.root, batch, results)
            for entry in batch['records'].values():
                reason = ai_block_reason(batch['locale'], 'globalstrings', entry['id'], 'name', entry['source'], evidence)
                if reason:
                    raise ValueError(reason + ': client label ' + entry['id'])
            if args.command == 'check-labels':
                print('Validated client-label translations')
            else:
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(labels.patch(args.root, batch, results))
                print('Generated client-label patch; apply it with apply_patch')
        return

    if args.command == 'prepare':
        scope = read_json(args.scope)
        batches = prepare_batches(args.root, scope, args.batch_size)
        args.output_dir.mkdir(parents=True, exist_ok=True)
        destinations = [args.output_dir / (f'{index:05d}' + suffix)
                        for index in range(len(batches)) for suffix in ('.batch.json', '.results.json')]
        destinations.append(args.output_dir / 'manifest.json')

        if any(path.exists() for path in destinations):
            parser.error('Output files already exist; use a new batch directory to preserve saved work')

        manifest = []

        for index, batch in enumerate(batches):
            stem = f'{index:05d}'
            (args.output_dir / (stem + '.batch.json')).write_text(dump_json(batch), encoding='utf-8')
            (args.output_dir / (stem + '.results.json')).write_text(dump_json(batch['records']), encoding='utf-8')
            manifest.append({'batch': stem + '.batch.json', 'results': stem + '.results.json',
                             'batchHash': batch['batchHash']})

        (args.output_dir / 'manifest.json').write_text(dump_json(manifest), encoding='utf-8')
        print(f'Prepared {len(batches)} isolated catalog batches')
        return

    batch = read_json(args.batch)
    results = read_json(args.results)
    if args.command == 'patch-dialogue':
        from tools.catalogs.dialogue_jobs import merge_translations
        results = merge_translations(batch, results, GET_DIALOGUE_TOKENS)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(create_patch(args.root, batch, results, compact=True))
        print('Generated validated quest-dialogue patch')
        return
    validate_batch(args.root, batch, results)
    from tools.catalogs.import_policy import OfficialEvidence, validate_batch_policy
    validate_batch_policy(batch, results, OfficialEvidence(args.database, args.root) if args.database else None)

    if args.command == 'patch':
        patch = create_patch(args.root, batch, results)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(patch, encoding='utf-8')
        print('Generated catalog patch; apply it with the dedicated apply_patch tool')
        return

    pairs = validate_batch(args.root, batch, results)
    print(f'Validated {len(pairs)} assigned entities against current catalog records')


if __name__ == '__main__':
    main()
