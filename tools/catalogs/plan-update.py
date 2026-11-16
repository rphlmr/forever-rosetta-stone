"""Compare frozen native evidence and prepare a review-only update handoff."""

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.catalogs.catalog_storage import KINDS, get_entity_path, read_json
from datasources.corpus.translation_corpus import normalize_quest_linebreaks

ROOT = Path(__file__).resolve().parents[2]


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def file_sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def text_hash(value):
    return None if value is None else sha(value.encode('utf-8'))


def corpus_identity(path, root):
    path = Path(path).resolve()
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    try:
        settings = {r['key']: json.loads(r['value']) for r in db.execute('SELECT key,value FROM settings')}
        if settings.get('schemaVersion') != 1 or not isinstance(settings.get('fingerprint'), str):
            raise ValueError('Unsupported corpus schema or missing fingerprint')
        inputs = {}
        for row in db.execute("SELECT path,sha256 FROM inputs WHERE path NOT LIKE 'catalogs/%' ORDER BY path"):
            rel = Path(row['path'])
            source = (root / rel).resolve()
            if rel.is_absolute() or not source.is_relative_to(root) or not source.is_file():
                raise ValueError('Missing or unsafe external input: ' + str(rel))
            if file_sha(source) != row['sha256']:
                raise ValueError('Stale external input: ' + str(rel))
            inputs[str(rel)] = row['sha256']
        return {'path': str(path), 'sha256': file_sha(path),
                'fingerprint': settings['fingerprint'], 'externalInputs': inputs}
    finally:
        db.close()


def corpus(path, root, kinds=None, fields=None, locales=None):
    identity = corpus_identity(path, root)
    db = sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    try:
        conditions = ["evidence='sourceSnapshot'"]
        args = []
        for column, selection in [('kind', kinds), ('field', fields), ('locale', locales)]:
            if selection:
                conditions.append(column + ' IN (' + ','.join('?' for _ in selection) + ')')
                args.extend(selection)
        rows = defaultdict(list)
        for row in db.execute('SELECT kind,entity_id,locale,field,text,english,origin,provenance,flags FROM records WHERE '
                              + ' AND '.join(conditions), args):
            provenance = json.loads(row['provenance'])
            provider = provenance.get('source')
            if not provider or not isinstance(row['text'], str):
                raise ValueError('Source snapshot lacks provider or text')
            key = (row['kind'], str(row['entity_id']), row['locale'], row['field'], provider)
            rows[key].append({'text': row['text'], 'english': row['english'],
                              'origin': row['origin'], 'flags': json.loads(row['flags'])})
        return identity, rows
    finally:
        db.close()


def field_value(entity, locale, field):
    localized = entity.get('locales', {}).get(locale, {}) if entity else {}
    if field.startswith('objectiveLines.'):
        index = int(field.split('.', 1)[1])
        value = next((r.get('text') for r in localized.get('objectiveLines', []) if r.get('index') == index), None)
    else:
        value = localized.get(field)
    metadata = localized.get('translationMetadata', {}).get('fields', {}).get(field)
    return value, metadata


def normalized(candidates):
    return sorted({row['text'] for row in candidates})


def variants(candidates):
    values = {(row['text'], row['english'], row['origin'], tuple(sorted(row['flags']))) for row in candidates}
    return [{'text': text, 'english': english, 'origin': origin, 'flags': list(flags)}
            for text, english, origin, flags in sorted(values, key=lambda v: (v[0], v[1] or '', v[2], v[3]))]


def comparable(kind, value):
    if value is None or kind != 'quests':
        return value
    value = normalize_quest_linebreaks(value)
    for source, target in (('$B', '\n'), ('$b', '\n'), ('$n', '{name}'), ('$N', '{name}'),
                           ('$c', '{class}'), ('$C', '{class}'), ('$r', '{race}'), ('$R', '{race}')):
        value = value.replace(source, target)
    return re.sub(r'\s+', ' ', value).strip()


def plan(root, old_path, new_path, kinds=None, fields=None, locales=None):
    root = Path(root).resolve()
    old_info, old = corpus(old_path, root, kinds, fields, locales) if old_path else (None, defaultdict(list))
    new_info, new = corpus(new_path, root, kinds, fields, locales)
    configured = read_json(root / 'catalogs/quests/metadata.json')['document']['locales']
    configured = list(dict.fromkeys(locale for locale in configured if locale != 'enGB'))
    entities, changes, fill, review, selection, new_entities = {}, [], [], [], defaultdict(set), defaultdict(list)
    native_fields = {key[:4] for key, rows in new.items() if any(row['origin'] == 'original' for row in rows)}
    for key in sorted(set(old) | set(new)):
        before, after = normalized(old[key]), normalized(new[key])
        old_flags = sorted({flag for row in old[key] for flag in row['flags']})
        new_flags = sorted({flag for row in new[key] for flag in row['flags']})
        old_origins = sorted({row['origin'] for row in old[key]})
        new_origins = sorted({row['origin'] for row in new[key]})
        old_context = sorted({row['english'] for row in old[key]}, key=lambda v: (v is not None, v or ''))
        new_context = sorted({row['english'] for row in new[key]}, key=lambda v: (v is not None, v or ''))
        old_variants, new_variants = variants(old[key]), variants(new[key])
        if old_variants == new_variants and len(old_variants) <= 1:
            continue
        kind, entity_id, locale, field, provider = key
        if kind not in KINDS:
            raise ValueError('Unknown catalog kind: ' + kind)
        identity = (kind, entity_id)
        if identity not in entities:
            path = get_entity_path(root, kind, entity_id)
            raw = path.read_bytes() if path.exists() else None
            entities[identity] = (raw, json.loads(raw) if raw else None)
        raw, entity = entities[identity]
        target, metadata = field_value(entity, locale, field)
        conflict = len(old_variants) > 1 or len(new_variants) > 1
        status = 'conflict' if conflict else 'added' if not before else 'removed' if not after else 'changed'
        if before == after and not conflict:
            status = ('contextChanged' if old_context != new_context else
                      'originChanged' if old_origins != new_origins else 'flagsChanged')
        manual_conflict = bool(target is not None and comparable(kind, target) not in
                               {comparable(kind, v) for v in before + after})
        entry = {'kind': kind, 'id': entity_id, 'locale': locale, 'field': field, 'provider': provider,
                 'status': status, 'old': before, 'new': after,
                 'oldSha256': [text_hash(v) for v in before], 'newSha256': [text_hash(v) for v in after],
                 'oldFlags': old_flags, 'newFlags': new_flags, 'ownedTextSha256': text_hash(target),
                 'oldOrigins': old_origins, 'newOrigins': new_origins,
                 'oldEnglishContext': old_context, 'newEnglishContext': new_context,
                 'oldCandidates': old_variants, 'newCandidates': new_variants,
                 'ownedMetadata': metadata, 'manualOrOwnedConflict': manual_conflict,
                 'requiresReview': True}
        changes.append(entry)
        if entity is None:
            new_entities[identity].append(entry)
        if (status in ('added', 'changed') and not new_flags and not conflict and entity is not None
                and new_origins and set(new_origins) <= {'original', 'community'}
                and ('original' in new_origins or key[:4] not in native_fields)):
            # This is a proposal only, including owned conflicts, never an instruction to apply.
            fill.append(list(key))
        if entity is not None:
            selection[kind].add(entity_id)
            targets = []
            for candidate_locale in configured:
                _, candidate_metadata = field_value(entity, candidate_locale, field)
                if (locale == 'enUS' or candidate_locale == locale or
                        isinstance(candidate_metadata, dict) and candidate_metadata.get('sourceLocale') == locale):
                    targets.append(candidate_locale)
            for target_locale in targets:
                value, origin = field_value(entity, target_locale, field)
                review.append({'kind': kind, 'id': entity_id, 'field': field, 'locale': target_locale,
                               'sourceLocale': locale, 'provider': provider, 'sourceStatus': status,
                               'sourceSha256': [text_hash(v) for v in after],
                               'targetStatus': 'missing' if value is None else 'existing',
                               'targetSha256': text_hash(value), 'targetMetadata': origin,
                               'requiresReview': True})
    snapshots = [{'kind': k, 'id': i, 'sha256': sha(raw) if raw is not None else None}
                 for (k, i), (raw, _) in sorted(entities.items())]
    return {'schemaVersion': 1, 'oldCorpus': old_info, 'newCorpus': new_info,
            'filters': {'kinds': kinds, 'fields': fields, 'locales': locales},
            'localeConfigSha256': sha((root / 'catalogs/quests/metadata.json').read_bytes()),
            'entitySnapshots': snapshots, 'changes': changes, 'fillScope': fill,
            'translationScope': {k: sorted(v, key=int) for k, v in sorted(selection.items())},
            'newEntityCandidates': [{'kind': k, 'id': i, 'changes': entries}
                                    for (k, i), entries in sorted(new_entities.items())],
            'fieldReview': review}


def verify(plan_data, root):
    root = Path(root).resolve()
    for label in ('oldCorpus', 'newCorpus'):
        saved = plan_data[label]
        path = Path(saved['path'])
        if not path.is_file() or file_sha(path) != saved['sha256']:
            raise ValueError('Stale corpus: ' + str(path))
        current = corpus_identity(path, root)
        if current != saved:
            raise ValueError('Corpus identity changed: ' + str(path))
    if sha((root / 'catalogs/quests/metadata.json').read_bytes()) != plan_data['localeConfigSha256']:
        raise ValueError('Locale configuration changed')
    for entity in plan_data['entitySnapshots']:
        path = get_entity_path(root, entity['kind'], entity['id'])
        current = sha(path.read_bytes()) if path.exists() else None
        if current != entity['sha256']:
            raise ValueError('Owned entity changed: ' + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare')
    prepare.add_argument('--old', required=True, type=Path)
    prepare.add_argument('--new', required=True, type=Path)
    prepare.add_argument('--output-dir', required=True, type=Path)
    prepare.add_argument('--kind', nargs='+', choices=KINDS)
    prepare.add_argument('--field', nargs='+')
    prepare.add_argument('--locale', nargs='+')
    check = commands.add_parser('verify')
    check.add_argument('--plan', required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'verify':
            verify(read_json(args.plan), args.root)
            print('Plan inputs verified; decisions still require review.')
        else:
            output = args.output_dir.resolve()
            if not output.is_relative_to((args.root.resolve() / 'datasources/imports')) or output.exists():
                raise ValueError('Use a new output directory under datasources/imports/')
            result = plan(args.root, args.old, args.new, args.kind, args.field, args.locale)
            output.mkdir(parents=True)
            for name, data in [('plan.json', result), ('changes.json', result['changes']),
                               ('fill-scope.json', result['fillScope']),
                               ('translation-scope.json', result['translationScope']),
                               ('new-entity-candidates.json', result['newEntityCandidates']),
                               ('field-review.json', result['fieldReview'])]:
                (output / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
            print(f"Prepared {len(result['changes'])} review changes in {output}")
    except (ValueError, OSError, sqlite3.Error, KeyError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
