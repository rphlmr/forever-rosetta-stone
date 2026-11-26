"""Generate bulk catalog patches from verified official text in the SQLite corpus."""

import argparse
import collections
import copy
import difflib
import hashlib
import itertools
import json
import re
import runpy
import time
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.catalogs.catalog_storage import KINDS, dump_json, get_entity_path, read_json
from datasources.corpus.translation_corpus import open_corpus
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES
from tools.catalogs.official_text import OFFICIAL_LOCALES, SOURCE_PROVIDERS, preferred_source_rows, newer_core_source


ROOT = Path(__file__).resolve().parents[2]
quest_tokens = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))['get_quest_tokens']


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def comparable_text(text):
    if text is None:
        return None

    for source, target in (('$B', '\n'), ('$b', '\n'), ('$n', '{name}'), ('$N', '{name}'),
                           ('$c', '{class}'), ('$C', '{class}'), ('$r', '{race}'), ('$R', '{race}')):
        text = text.replace(source, target)

    return re.sub(r'\s+', ' ', text).strip()


def update_entity(entity, candidates, update_english=False):
    """Apply applicable trusted text, with reviewed English changes enabled explicitly."""
    result = copy.deepcopy(entity)
    counts = collections.Counter()
    english = result['locales'].setdefault('enUS', {})
    candidates = sorted(candidates, key=lambda row: (row['locale'] != 'enUS', row['locale'], row['field']))

    for (locale, field), rows in itertools.groupby(candidates, lambda row: (row['locale'], row['field'])):
        rows = preferred_source_rows(rows)
        original = [row for row in rows if row['origin'] == 'original']
        community = [row for row in rows if row['origin'] == 'community']
        native_original = [row for row in original if locale == 'enUS'
                           or comparable_text(row['text']) != comparable_text(row['english'])]
        native_community = [row for row in community if locale == 'enUS'
                            or comparable_text(row['text']) != comparable_text(row['english'])]
        rows = native_original or native_community or original or community or rows
        server_rows = [row for row in rows if json.loads(row['provenance']).get('source') == 'egLink']
        rows = server_rows or rows

        texts = {row['text'] for row in rows}

        if len(texts) != 1:
            counts['conflictingSources'] += 1
            continue

        row = rows[0]
        provenance = json.loads(row['provenance'])
        origin = row['origin']
        text = row['text']

        if (not text.strip() or '$@null' in text or '<NO LOG DESCRIPTION>' in text
                or re.search(r'\bNAME\b', text)
                or (field in ('name', 'title') and text.strip().lower() == 'unknown')):
            counts['unresolvedSourceTemplate'] += 1
            continue

        prior = result['locales'].get(locale, {}).get('translationMetadata', {}).get('fields', {}).get(field, {})
        needs_context = field not in ('name', 'title') or prior.get('canonicalEnglishSha256')
        if needs_context and locale != 'enUS' and english.get(field) \
                and comparable_text(row['english']) != comparable_text(english[field]):
            counts['sourceContextMismatch'] += 1
            continue

        if origin == 'community' and locale != 'enUS' and field not in ('name', 'title') and english.get(field):
            try:
                compatible = quest_tokens(text) == quest_tokens(english[field])
            except ValueError:
                compatible = False
            if not compatible:
                counts['communityPlaceholderMismatch'] += 1
                continue

        localized = result['locales'].setdefault(locale, {})
        current = localized.get(field)
        metadata = localized.get('translationMetadata', {}).get('fields', {}).get(field, {})
        if (metadata.get('origin') in ('original', 'community')
                and newer_core_source(metadata, provenance)):
            counts['preservedNewerSource'] += 1
            continue
        if locale != 'enUS' and not english.get(field):
            counts['excludedWithoutEnglishSource'] += 1
            continue

        if current and locale == 'enUS' and re.search(r'\|\d', text):
            counts['preservedUnsupportedClientMarkup'] += 1
            continue

        if locale == 'enUS' and current and comparable_text(current) == comparable_text(text):
            text = current

        # Questie owns summaries; the other core providers do not supply this field.
        unowned_summary = (field == 'summary' and metadata.get('source') in SOURCE_PROVIDERS - {'questie'})
        current_is_english = comparable_text(current) == comparable_text(english.get(field))
        candidate_is_english = locale != 'enUS' and comparable_text(text) == comparable_text(english.get(field))
        if (candidate_is_english and current and not current_is_english
                and (metadata.get('origin') in ('original', 'community', 'ai') or locale not in OFFICIAL_LOCALES)
                and (locale not in OFFICIAL_LOCALES or not unowned_summary)):
            counts['preservedLocalizedSource'] += 1
            continue
        candidate_is_newer = newer_core_source(provenance, metadata)
        if (origin != 'original' and metadata.get('origin') == 'original' and not unowned_summary
                and not candidate_is_newer
                and not (locale != 'enUS' and current_is_english and not candidate_is_english)):
            counts['preservedPreferredOfficial'] += 1
            continue

        if current == text and metadata.get('origin') == origin and not candidate_is_newer:
            counts['alreadyOfficial' if origin == 'original' else 'alreadyCommunity'] += 1
            continue

        if not update_english and field not in ('name', 'title') and locale == 'enUS' and current and current != text \
                and metadata.get('origin') != 'ai':
            counts['preservedCanonicalEnglish'] += 1
            continue

        localized[field] = text
        localized.setdefault('translationMetadata', {}).setdefault('fields', {})[field] = {
            'origin': origin,
            **{key: provenance[key] for key in ('source', 'sourceLocale', 'sourceBuild', 'sourceRevision', 'sourceNamespace')
               if key in provenance},
        }
        counts['filled' if not current else 'provenanceVerified' if current == text else 'replaced'] += 1

    return result, counts


def patch_text(path, before, after):
    lines = list(difflib.unified_diff(before.splitlines(True), after.splitlines(True), n=3))

    return '*** Update File: ' + str(path) + '\n' + ''.join(
        '@@\n' if line.startswith('@@') else line for line in lines[2:])


def source_rows(db, kinds=None, include_community=True, entity=None, flagged=False, scope=None):
    conditions, values = ["evidence='sourceSnapshot'", "origin IN (" + ('?,?' if include_community else '?') + ')'], []
    values.extend(('original', 'community') if include_community else ('original',))
    conditions.append("flags!='[]'" if flagged else "(flags='[]' OR origin='original')")

    if kinds:
        conditions.append('kind IN (' + ','.join('?' for _ in kinds) + ')')
        values.extend(kinds)

    if entity:
        conditions.extend(('kind=?', 'entity_id=?'))
        values.extend(entity)

    rows = db.execute('SELECT * FROM records WHERE ' + ' AND '.join(conditions)
                      + ' ORDER BY kind,entity_id,locale,field,id', values)

    def selected(row):
        flags = json.loads(row['flags'])
        known_locale_fallback = row['locale'] == 'itIT' and row['text'] == row['english']
        official_wording = row['origin'] == 'original' and not known_locale_fallback and all(flag == 'equalsEnglish:inspectBeforeReuse'
            or flag.startswith('sharedProseAcrossLanguages:') for flag in flags)
        if (not flagged and flags and not official_wording) or (flagged and official_wording):
            return False
        if scope is None:
            return True

        key = (row['kind'], row['entity_id'], row['locale'], row['field'])

        return key in scope or (*key, json.loads(row['provenance']).get('source')) in scope

    return (row for row in rows if selected(row))


def prepare(database, output, root=ROOT, chunk_size=5, kinds=None, include_community=True,
            scope=None, update_english=False):
    started = time.monotonic()
    root, output = Path(root).resolve(), Path(output).resolve()

    if not output.is_relative_to(root / 'datasources/imports') or output.exists():
        raise ValueError('Use a new output directory under datasources/imports/')

    db = open_corpus(database)
    output.mkdir(parents=True)
    counts = collections.Counter()
    changes, chunk, blocks = [], [], []

    def flush():
        if not chunk:
            return

        name = f'{len(changes):05d}'
        (output / (name + '.patch')).write_text('*** Begin Patch\n' + ''.join(blocks) + '*** End Patch\n')
        (output / (name + '.json')).write_text(dump_json(chunk))
        changes.append({'name': name, 'files': len(chunk)})
        chunk.clear()
        blocks.clear()

    try:
        for row in db.execute("SELECT path,sha256 FROM inputs WHERE path NOT LIKE 'catalogs/%'"):
            if sha256((root / row['path']).read_bytes()) != row['sha256']:
                raise ValueError('Source changed since corpus refresh: ' + row['path'])

        counts['flaggedSourceRowsSkipped'] = sum(1 for _ in source_rows(db, kinds, include_community,
                                                                     flagged=True, scope=scope))
        rows = source_rows(db, kinds, include_community, scope=scope)

        for (kind, entity_id), candidates in itertools.groupby(rows, lambda row: (row['kind'], row['entity_id'])):
            path = get_entity_path(root, kind, entity_id)

            if not path.exists():
                counts['sourceEntitiesOutsideCatalog'] += 1
                continue

            raw = path.read_bytes()
            before = read_json(path)

            if kind == 'quests' and before.get('usageStatus') in EXCLUDED_QUEST_STATUSES:
                counts['excludedQuestEntities'] += 1
                continue

            after, entity_counts = update_entity(before, candidates, update_english=update_english)
            counts.update(entity_counts)
            for key, value in entity_counts.items():
                counts[kind + '.' + key] += value
            counts[kind + '.checkedEntities'] += 1

            if before == after:
                continue

            replacement = dump_json(after)
            blocks.append(patch_text(path, raw.decode('utf-8'), replacement))
            chunk.append({'path': str(path.relative_to(root)), 'beforeSha256': sha256(raw),
                          'afterSha256': sha256(replacement.encode('utf-8'))})
            counts['changedFiles'] += 1

            if len(chunk) == chunk_size:
                flush()

        flush()
    finally:
        db.close()

    summary = {'seconds': round(time.monotonic() - started, 3), 'counts': dict(counts), 'chunks': changes,
               'database': str(Path(database).resolve()), 'aiTranslations': 0,
               'kinds': kinds, 'includeCommunity': include_community,
               'scope': sorted(scope) if scope is not None else None, 'updateEnglish': update_english,
               'policy': 'Selected external source snapshots only; origins retained; no new entities. '
                         + ('Scoped trusted updates replace older claims, including English; target prose requires matching context.'
                            if update_english else 'Canonical English prose is protected; target prose requires matching English context.')}
    (output / 'summary.json').write_text(dump_json(summary))

    return summary


def read_patch(directory, name, root=ROOT):
    directory = Path(directory)
    files = read_json(directory / (name + '.json'))

    for row in files:
        if sha256((Path(root) / row['path']).read_bytes()) != row['beforeSha256']:
            raise ValueError('Catalog changed since patch preparation: ' + row['path'])

    return {'patch': (directory / (name + '.patch')).read_text(), 'files': len(files)}


def verify(directory, root=ROOT):
    directory = Path(directory)
    summary = read_json(directory / 'summary.json')
    checked = 0

    for chunk in summary['chunks']:
        for row in read_json(directory / (chunk['name'] + '.json')):
            if sha256((Path(root) / row['path']).read_bytes()) != row['afterSha256']:
                raise ValueError('Catalog does not match generated official-source result: ' + row['path'])

            checked += 1

    return {'verifiedFiles': checked, 'counts': summary['counts']}


def apply_prepared(directory, root=ROOT):
    """Write deterministic generator output after checking both the original and expected result hashes."""
    started = time.monotonic()
    directory = Path(directory)
    summary = read_json(directory / 'summary.json')
    db = open_corpus(summary['database'])
    applied = 0
    scope = summary.get('scope')
    scope = {tuple(key) for key in scope} if scope is not None else None

    try:
        for chunk in summary['chunks']:
            for row in read_json(directory / (chunk['name'] + '.json')):
                path = Path(root) / row['path']
                raw = path.read_bytes()

                if sha256(raw) == row['afterSha256']:
                    continue

                if sha256(raw) != row['beforeSha256']:
                    raise ValueError('Catalog changed since source matching: ' + row['path'])

                candidates = source_rows(db, include_community=summary.get('includeCommunity', False),
                                         entity=(path.parent.name, path.stem),
                                         scope=scope)
                after, _ = update_entity(json.loads(raw), candidates, update_english=summary.get('updateEnglish', False))
                replacement = dump_json(after)

                if sha256(replacement.encode('utf-8')) != row['afterSha256']:
                    raise ValueError('Generated source result changed: ' + row['path'])

                path.write_text(replacement, encoding='utf-8')
                applied += 1
    finally:
        db.close()

    result = {'generatedFilesWritten': applied, 'seconds': round(time.monotonic() - started, 3),
              'counts': summary['counts'], 'aiTranslations': 0}
    (directory / 'applied.json').write_text(dump_json(result))

    return result


def audit_authored(database, output, root=ROOT):
    """Report AI fields for which an applicable official snapshot is now available; never write catalogs."""
    root, output = Path(root), Path(output)
    db = open_corpus(database)
    counts, findings = collections.Counter(), []
    try:
        for row in db.execute("SELECT path,sha256 FROM inputs WHERE path NOT LIKE 'catalogs/%'"):
            if sha256((root / row['path']).read_bytes()) != row['sha256']:
                raise ValueError('Source changed since corpus refresh: ' + row['path'])
        rows = source_rows(db, include_community=False)
        for (kind, entity_id), candidates in itertools.groupby(rows, lambda row: (row['kind'], row['entity_id'])):
            path = get_entity_path(root, kind, entity_id)
            if not path.is_file():
                continue
            before = read_json(path)
            if kind == 'quests' and before.get('usageStatus') in EXCLUDED_QUEST_STATUSES:
                counts['excludedQuestEntities'] += 1
                continue
            selected = []
            for row in candidates:
                entry = before.get('locales', {}).get(row['locale'], {})
                metadata = entry.get('translationMetadata', {}).get('fields', {}).get(row['field'], {})
                if row['locale'] in OFFICIAL_LOCALES and metadata.get('origin') == 'ai' and entry.get(row['field']):
                    selected.append(row)
            if not selected:
                continue
            after, outcome = update_entity(before, selected)
            counts.update(outcome)
            for locale, field in sorted({(row['locale'], row['field']) for row in selected}):
                entry = after['locales'][locale]
                metadata = entry.get('translationMetadata', {}).get('fields', {}).get(field, {})
                if metadata.get('origin') != 'original':
                    counts['unresolvedFields'] += 1
                    continue
                prior = before['locales'][locale][field]
                findings.append({'kind': kind, 'id': entity_id, 'locale': locale, 'field': field,
                                 'current': prior, 'official': entry[field], 'metadata': metadata,
                                 'textDiffers': comparable_text(prior) != comparable_text(entry[field])})
    finally:
        db.close()
    report = {'database': str(Path(database).resolve()), 'readOnly': True,
              'scope': 'AI fields in official locales with applicable original source snapshots; no catalog claims used as evidence.',
              'counts': dict(counts), 'fields': len(findings),
              'entities': len({(row['kind'],row['id']) for row in findings}),
              'normalizedTextDiffers': sum(row['textDiffers'] for row in findings),
              'findings': findings}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(dump_json(report))
    return {key:value for key,value in report.items() if key != 'findings'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    audit = commands.add_parser('audit-authored')
    audit.add_argument('--database', type=Path, required=True)
    audit.add_argument('--output', type=Path, required=True)
    create = commands.add_parser('prepare')
    create.add_argument('--database', type=Path, required=True)
    create.add_argument('--output', type=Path, required=True)
    create.add_argument('--chunk-size', type=int, default=5)
    create.add_argument('--kinds', nargs='+', choices=KINDS)
    create.add_argument('--include-community', action='store_true', default=True,
                        help='Include maintained community snapshots (the default); retain their actual origin')
    create.add_argument('--original-only', action='store_false', dest='include_community',
                        help='Limit candidates to original game text')
    create.add_argument('--scope', type=Path, help='JSON [kind, ID, locale, field] tuples, optionally ending in provider.')
    create.add_argument('--update-english', action='store_true', help='Accept scoped, reviewed English source updates.')

    for name in ('read-patch', 'verify', 'apply'):
        command = commands.add_parser(name)
        command.add_argument('--directory', type=Path, required=True)

        if name == 'read-patch':
            command.add_argument('--chunk', required=True)

    args = parser.parse_args()

    if args.command == 'audit-authored':
        result = audit_authored(args.database, args.output)
    elif args.command == 'prepare':
        if args.chunk_size < 1:
            parser.error('--chunk-size must be positive')

        if args.update_english and args.scope is None:
            parser.error('--update-english requires an explicit --scope')

        result = prepare(args.database, args.output, chunk_size=args.chunk_size,
                         kinds=args.kinds, include_community=args.include_community,
                         scope={tuple(key) for key in read_json(args.scope)} if args.scope else None,
                         update_english=args.update_english)
    elif args.command == 'read-patch':
        result = read_patch(args.directory, args.chunk)
    elif args.command == 'apply':
        result = apply_prepared(args.directory)
    else:
        result = verify(args.directory)

    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
