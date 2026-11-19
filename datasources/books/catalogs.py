"""Prepare sourced book catalogs for resync's immutable apply/verify boundary."""
import copy
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

from datasources.books.codex import export
from datasources.books.texts import normalized
from datasources.corpus.translation_corpus import open_corpus
from tools.catalogs.catalog_storage import dump_json
from tools.catalogs.import_policy import verify_sources
from tools.catalogs.official_text import OFFICIAL_LOCALES


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def item_title_reuse(root, english, provenance):
    """Reuse owned item names only for the selected item and exact English context."""
    if provenance.get('ownerKind') != 'item':
        return None, {}
    identifier = str(provenance.get('ownerId', ''))
    if not identifier.isdecimal():
        return None, {}
    path = Path(root) / 'catalogs/items' / (identifier + '.json')
    if not path.exists():
        return None, {}
    raw = path.read_bytes()
    locales = json.loads(raw).get('locales', {})
    if locales.get('enUS', {}).get('name') != english:
        return None, {}
    reusable = {}
    for locale, record in locales.items():
        metadata = record.get('translationMetadata', {}).get('fields', {}).get('name', {})
        if locale == 'enUS' or not record.get('name') or not metadata:
            continue
        if metadata.get('origin') not in ('original', 'community', 'ai'):
            continue
        if locale in OFFICIAL_LOCALES and metadata.get('origin') == 'ai':
            continue
        reusable[locale] = (record['name'], copy.deepcopy(metadata))
    return (str(path.relative_to(root)), sha(raw)), reusable


def prepare(root, database, output):
    root, output = Path(root).resolve(), Path(output).resolve()
    if not output.is_relative_to(root / 'datasources/imports') or output.exists():
        raise ValueError('Use a new book preparation directory under datasources/imports')
    database = verify_sources(database, root)
    connection = open_corpus(database)
    try:
        scope = connection.execute("SELECT value FROM settings WHERE key='scope'").fetchone()
        if not scope or json.loads(scope[0]) != 'book-texts':
            raise ValueError('Prepare books from a verified book-texts corpus')
        codex = export(connection)
        rows = defaultdict(list)
        for row in connection.execute("SELECT * FROM records WHERE kind IN ('books','bookpages') AND evidence='sourceSnapshot'"):
            rows[row['kind'], row['entity_id'], row['locale'], row['field']].append(dict(row))
        inputs = dict(connection.execute('SELECT path,sha256 FROM inputs'))
        source_issues = [json.loads(row[0]) for row in connection.execute('SELECT document FROM book_text_issues')]
    finally:
        connection.close()
    output.mkdir(parents=True)
    held, changes, files = [], [], []
    counts = Counter()
    reused_inputs = {}
    translation_scope = defaultdict(list)

    def choose(kind, identifier, locale, field, context=None):
        candidates = []
        for row in rows.get((kind, str(identifier), locale, field), []):
            flags = json.loads(row['flags'])
            if flags or (locale in OFFICIAL_LOCALES and row['origin'] == 'ai'):
                held.append({'kind': kind, 'id': identifier, 'locale': locale, 'field': field,
                             'reason': 'flaggedOrOfficialAI', 'flags': flags,
                             'source': json.loads(row['provenance']).get('source')})
                continue
            if context is not None and (not row['english'] or normalized(row['english']) != normalized(context)):
                held.append({'kind': kind, 'id': identifier, 'locale': locale, 'field': field, 'reason': 'englishContextMismatch'})
                continue
            provenance = json.loads(row['provenance'])
            source_rank = {'egLink': 0, 'wago': 0, 'wowhead': 1, 'vmangos': 2,
                           'cmangos': 3, 'azerothcore': 4}.get(provenance['source'], 5)
            rank = (row['origin'] == 'ai', source_rank)
            candidates.append((rank, row, provenance))
        if not candidates:
            return None
        rank = min(c[0] for c in candidates)
        best = [c for c in candidates if c[0] == rank]
        if len({c[1]['text'] for c in best}) > 1:
            held.append({'kind': kind, 'id': identifier, 'locale': locale, 'field': field, 'reason': 'competingSourceWording'})
            return None
        _, row, provenance = best[0]
        metadata = {**provenance, 'origin': row['origin'],
                    'sourceInputSha256': inputs[row['source_path']]}
        return row['text'], metadata

    def stage(relative, document):
        path = root / relative
        before = path.read_bytes() if path.exists() else None
        raw = dump_json(document).encode()
        if before == raw:
            return
        result = f'{len(files):05d}.json'
        (output / result).write_bytes(raw)
        files.append({'path': relative, 'result': result,
                      'beforeSha256': sha(before) if before is not None else None, 'afterSha256': sha(raw)})

    source_pages = {}
    for book in codex['books']:
        for page in book['pages']:
            entry = source_pages.setdefault(page['id'], {'page': page, 'books': []})
            entry['books'].append(book['firstPageId'])
    entities = [('books', book['firstPageId'], book) for book in codex['books']]
    entities += [('bookpages', page, context) for page, context in sorted(source_pages.items())]
    available_locales = sorted({key[2] for key in rows})
    for kind, identifier, source in entities:
        path = root / f'catalogs/{kind}/{identifier}.json'
        before = json.loads(path.read_bytes()) if path.exists() else {'locales': {}}
        after = copy.deepcopy(before)
        field = 'name' if kind == 'books' else 'description'
        english = choose(kind, identifier, 'enUS', field)
        if not english:
            counts['missingEnglishEntities'] += 1
            continue
        current_english = after['locales'].get('enUS', {}).get(field)
        if current_english and normalized(current_english) != normalized(english[0]):
            held.append({'kind': kind, 'id': identifier, 'locale': 'enUS', 'field': field, 'reason': 'preserveOwnedEnglish'})
            continue
        translation_scope[kind].append(str(identifier))
        reused = {}
        if kind == 'books':
            reuse_input, reused = item_title_reuse(root, english[0], english[1])
            if reuse_input:
                reused_inputs[reuse_input[0]] = reuse_input[1]
        locales = sorted(set(available_locales) | set(reused))
        for locale in ['enUS', *[l for l in locales if l != 'enUS']]:
            selected = english if locale == 'enUS' else choose(kind, identifier, locale, field, english[0])
            if selected is None:
                selected = reused.get(locale)
            if selected is None:
                continue
            text, provenance = selected
            record = after['locales'].setdefault(locale, {})
            previous_text = record.get(field)
            if field in record:
                current_origin = record.get('translationMetadata', {}).get('fields', {}).get(field, {}).get('origin')
                replace_ai = locale != 'enUS' and current_origin == 'ai' and provenance['origin'] in ('original', 'community')
                if not replace_ai and previous_text != text:
                    held.append({'kind': kind, 'id': identifier, 'locale': locale, 'field': field, 'reason': 'preserveAcceptedTranslation'})
                if not replace_ai:
                    continue
            record[field] = text
            record.setdefault('translationMetadata', {}).setdefault('fields', {})[field] = provenance
            changes.append({'kind': kind, 'id': identifier, 'locale': locale, 'field': field,
                            'before': previous_text, 'after': text, 'metadata': provenance})
            counts[locale] += 1
        if kind == 'books':
            structure = {'owners': [{'kind': o['kind'], 'id': o['id']} for o in source['owners']],
                         'pages': [p['id'] for p in source['pages']], 'chainStatus': source['chainStatus'],
                         'foreverPageSequenceVerified': False}
            if 'owners' not in after:
                after.update(structure)
                after['ownerNames'] = {o['kind'] + ':' + str(o['id']): {
                    'name': o['title'], 'source': o['observations'][-1]} for o in source['owners']}
                first_page = source['pages'][0] if source['pages'] else {}
                after['pageChainMetadata'] = {'source': first_page.get('source', 'vmangos'),
                    'scope': first_page.get('scope', 'vanillaReference'),
                    **{k: first_page[k] for k in ('assetID', 'patch') if k in first_page}}
            elif (not after.get('pages') and source['pages'] and
                  source['pages'][0].get('scope') == 'observedFirstPage' and structure['owners'] == after['owners']):
                after['pages'] = structure['pages']
                after['pageChainMetadata'] = {k: source['pages'][0][k] for k in ('source', 'scope')}
            elif any(after.get(k) != v for k, v in structure.items()):
                held.append({'kind': kind, 'id': identifier, 'reason': 'preserveOwnedStructure'})
        else:
            if 'linkMetadata' not in after:
                page = source['page']
                if 'nextPageId' in page:
                    after['nextPageId'] = page['nextPageId']
                after.update(bookIds=sorted(source['books']),
                             linkMetadata={k: page[k] for k in ('source', 'assetID', 'patch', 'scope') if k in page})
        stage(str(path.relative_to(root)), after)
    for kind in ('books', 'bookpages'):
        metadata_path = root / f'catalogs/{kind}/metadata.json'
        if not metadata_path.exists():
            stage(str(metadata_path.relative_to(root)), {'storageVersion': 2, 'kinds': [kind],
                                                       'document': {'schemaVersion': 1}})
    policy_paths = ['datasources/books/catalogs.py', 'datasources/books/texts.py', 'datasources/books/archives.py',
                    'tools/catalogs/import_policy.py', 'tools/catalogs/official_text.py']
    manifest = {'database': str(database), 'databaseSha256': sha(database.read_bytes()), 'files': files,
                'scope': 'book-texts', 'unresolvedFields': 0, 'heldConflicts': len(held),
                'counts': dict(counts), 'changedFields': len(changes),
                'policyInputs': {**{p: sha((root / p).read_bytes()) for p in policy_paths if (root / p).exists()},
                                 **reused_inputs}}
    for name, document in [('manifest.json', manifest), ('changes.json', changes),
                           ('held-source-conflicts.json', held), ('source-issues.json', source_issues),
                           ('unresolved.json', []), ('translation-scope.json', dict(translation_scope))]:
        (output / name).write_text(dump_json(document))
    return {k: v for k, v in manifest.items() if k not in ('files', 'policyInputs')} | {'changedFiles': len(files)}
