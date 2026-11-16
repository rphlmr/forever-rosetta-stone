"""Attach existing source wording to codex/page IDs; never generate translations."""
import csv
import hashlib
import html
import io
import json
import re
import sqlite3
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

from datasources.github_community import polish_hash
from datasources.lua_data import assignments
from datasources.wago.loader import parse_version

BOOK_PROVIDERS = ('classic-ua', 'czech-forever', 'polish-forever', 'forever-tr',
                  'wow-lang', 'wow-forever-it', 'questtranslator-tr')
VM_LOCALES = {'koKR': 1, 'frFR': 2, 'deDE': 3, 'zhCN': 4, 'zhTW': 5,
              'esES': 6, 'esMX': 7, 'ruRU': 8}
HTML_TAG = re.compile(r'</?(?:html|body|p|br|h[1-6]|img|table|tr|td|div|span|font|a|b|i|ul|ol|li)\b[^>]*>', re.I)


def normalized(text):
    return ' '.join(html.unescape(HTML_TAG.sub(' ', text)).replace('$B', ' ').replace('$b', ' ').split())


def useful(text):
    return isinstance(text, str) and bool(normalized(text)) and normalized(text).lower() != 'missing text'


def czech_key(text):
    # Upstream Text.SourceKey: ASCII lowercase, omit selector/player codes, djb2.
    text = re.sub(r'\$g[^;]*;', '', text.lower())
    text = re.sub(r'\$[a-z]', '', text)
    text = re.sub('[^a-z0-9]', '', text)
    value = 5381
    for byte in text.encode():
        value = (value * 33 + byte) % 4294967296
    return f'{value:08x}'


def turkish_key(text):
    text = re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', text)
    text = re.sub(r'\|[TA].*?\|[ta]', '', text)
    text = re.sub(r'\|H.*?\|h(.*?)\|h', r'\1', text).replace('|n', ' ')
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    text = re.sub(r'\$[bB]', '\n', text)
    text = re.sub(r'\s*\n\s*', ' $B ', text)
    text = re.sub(r'\$n(?![A-Za-z])', '$N', text)
    text = re.sub(r'[ \t\n\r\v\f]+', ' ', text.replace('\u00a0', ' ')).strip(' ')
    text = re.sub(r'(?<!\$)[A-Z]', lambda m: m[0].lower(), text)
    value = 2166136261
    for byte in text.encode():
        value = ((value ^ byte) * 16777619) % 4294967296
    return value


def ingest(builder, config, codex):
    root, read = builder.root, builder.read
    issues = []
    english = {}
    books = {b['firstPageId']: b for b in codex['books']}
    canonical = {}
    page_ids = {p['id'] for book in books.values() for p in book['pages']}
    owners = {(o['kind'], o['id']): (book, o) for book in books.values() for o in book['owners']}

    def input_path(relative):
        path = (root / relative).resolve()
        if not path.is_relative_to(root / 'datasources/imports'):
            raise ValueError('Book text input outside datasources/imports')
        return path

    def add(kind, identifier, locale, field, text, origin, provenance, path, context=None, flags=()):
        if not useful(text):
            return
        flags = list(flags)
        if locale != 'enUS' and context is not None and normalized(text) == normalized(context):
            issues.append({'kind': kind, 'id': identifier, 'locale': locale, 'reason': 'englishFallback'})
            return
        if re.search(r'\$O\(|@\[|@<|\[\[', text):
            flags.append('unsupportedBookMarkup')
        provenance = {**provenance, 'sourceLocale': locale,
                      'sourceTextSha256': hashlib.sha256(text.encode()).hexdigest()}
        if context is not None:
            provenance['englishSha256'] = hashlib.sha256(context.encode()).hexdigest()
        builder.add(kind, str(identifier), locale, field, text, context, origin, 'sourceSnapshot', provenance, path, flags)

    ranks = {'egLink': 0, 'wago': 1, 'vmangos': 2}
    for first, book in books.items():
        owner = min(book['owners'], key=lambda o: (ranks[o['selectedSource']], o['kind'], o['id']))
        canonical[first] = owner
        observation = owner['observations'][-1]
        source = observation['source']
        provenance = {'source': source, 'ownerKind': owner['kind'], 'ownerId': owner['id'],
                      'sourceBuild': observation.get('build'), 'sourceRevision': observation.get('revision'),
                      'assetID': observation.get('assetID'), 'scope': owner['status']}
        add('books', first, 'enUS', 'name', owner['title'],
            'community' if source == 'vmangos' else 'original',
            {k: v for k, v in provenance.items() if v is not None}, input_path(observation['path']))

    for entry in config.get('vmangos', []):
        directory = input_path(entry['path'])
        database = directory / 'mangos.sqlite'
        # Codex ingestion already verified every manifest input; include the exact database
        # in the same input inventory rather than treating its projection as text evidence.
        read(database)
        connection = sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)
        connection.row_factory = sqlite3.Row
        provenance = {'source': 'vmangos', 'sourceRevision': entry['pin']['assetName'],
                      'assetID': entry['pin']['assetID'], 'scope': 'vanillaReference'}
        try:
            for row in connection.execute('SELECT entry,text FROM page_text'):
                if row['entry'] in page_ids and useful(row['text']):
                    english[row['entry']] = row['text']
                    add('bookpages', row['entry'], 'enUS', 'description', row['text'], 'community',
                        {**provenance, 'sourceRecord': row['entry']}, database, row['text'])
            for row in connection.execute('SELECT * FROM locales_page_text'):
                page = row['entry']
                if page not in english:
                    continue
                for locale, index in VM_LOCALES.items():
                    add('bookpages', page, locale, 'description', row['Text_loc' + str(index)], 'community',
                        {**provenance, 'sourceRecord': page}, database, english[page])
            localized_owners = {}
            for kind, table in [('item', 'locales_item'), ('object', 'locales_gameobject')]:
                needed = {o['id'] for o in canonical.values() if o['kind'] == kind}
                for row in connection.execute('SELECT * FROM ' + table):
                    if row['entry'] in needed:
                        localized_owners[kind, row['entry']] = dict(row)
            for first, owner in canonical.items():
                vm = next((o for o in owner['observations'] if o['source'] == 'vmangos'), None)
                # A changed Forever title does not authorize reusing the old localized title.
                if not vm or vm['title'] != owner['title'] or vm['firstPageId'] != first:
                    continue
                row = localized_owners.get((owner['kind'], owner['id']), {})
                for locale, index in VM_LOCALES.items():
                    add('books', first, locale, 'name', row.get('name_loc' + str(index)), 'community',
                        {**provenance, 'ownerKind': owner['kind'], 'ownerId': owner['id']}, database, owner['title'])
        finally:
            connection.close()

    # Only titles of the selected item owner are reused, with an exact English-name guard.
    for relative in config.get('wago', []):
        directory = input_path(relative)
        manifest = json.loads(read(directory / 'manifest.json'))
        selected = {o['id']: first for first, o in canonical.items() if o['kind'] == 'item'}
        native_names = {}
        for item in sorted(manifest['results'], key=lambda item: item['locale'] != 'enUS'):
            if item['table'] != 'ItemSparse' or item.get('status') not in ('downloaded', 'existing'):
                continue
            target = (directory / item['file']).resolve()
            if not target.is_relative_to(directory):
                raise ValueError('Invalid localized Wago book path')
            raw = read(target)
            if hashlib.sha256(raw).hexdigest() != item['sha256']:
                raise ValueError('Localized Wago book hash mismatch')
            for row in csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))):
                identifier = int(row['ID'])
                if identifier not in selected:
                    continue
                first = selected[identifier]
                if int(row['PageID']) != first:
                    raise ValueError('Localized Wago book page identity differs')
                locale = item['locale']
                if locale == 'enUS':
                    native_names[identifier] = row['Display_lang']
                    continue
                if native_names.get(identifier) != canonical[first]['title']:
                    continue
                add('books', first, locale, 'name', row['Display_lang'], 'original',
                    {'source': 'wago', 'sourceBuild': manifest['build'], 'ownerKind': 'item',
                     'ownerId': identifier}, target, native_names[identifier])

    # Client captures have owner ID + ordinal, not page IDs. Bind only when the reference
    # page at that ordinal agrees in wording; a shifted/changed chain stays in review.
    observations = {}
    for entry in config.get('egBookTexts', []):
        path = input_path(entry['path'])
        document = json.loads(read(path))
        meta = document['meta']
        if meta.get('product') != 'wowf' or meta.get('dataset') != 'texts' or meta.get('schemaVersion') != 1:
            raise ValueError('Unsupported EG book text schema')
        for owner_key, pages in document.get('books', {}).items():
            match = re.fullmatch(r'(item|object):([1-9]\d*)', owner_key)
            if not match:
                issues.append({'reason': 'untypedCapturedOwner', 'owner': owner_key})
                continue
            known = owners.get((match[1], int(match[2])))
            if not known:
                continue
            book, owner = known
            for ordinal, record in pages.items():
                position = int(ordinal) - 1
                if position < 0 or position >= len(book['pages']):
                    issues.append({'reason': 'unboundCapturedPage', 'owner': owner_key, 'ordinal': ordinal})
                    continue
                page = book['pages'][position]['id']
                for variant in record.get('texts', []):
                    text = variant['text']
                    if page not in english or normalized(text) != normalized(english[page]):
                        issues.append({'reason': 'capturedEnglishMismatch', 'owner': owner_key,
                                       'ordinal': ordinal, 'pageId': page, 'build': meta['clientBuild']})
                        continue
                    key = (page, meta['locale'])
                    candidate = (parse_version(meta['clientBuild']), text, entry, path, owner_key, ordinal)
                    observations.setdefault(key, []).append(candidate)
    for (page, locale), values in observations.items():
        newest = max(v[0] for v in values)
        values = [v for v in values if v[0] == newest]
        if len({v[1] for v in values}) != 1:
            issues.append({'reason': 'conflictingCapturedVariants', 'pageId': page, 'locale': locale})
            continue
        _, text, entry, path, owner, ordinal = values[0]
        add('bookpages', page, locale, 'description', text, 'original',
            {'source': 'egLink', 'sourceBuild': '.'.join(map(str, newest)), 'sourceRevision': entry['revision'],
             'owner': owner, 'pageOrdinal': int(ordinal), 'scope': 'foreverObservation'}, path, english[page])

    ingest_community(builder, config, codex, english, add, issues, input_path)
    builder.db.execute('CREATE TABLE book_text_issues (document TEXT NOT NULL)')
    builder.db.executemany('INSERT INTO book_text_issues VALUES (?)', [(json.dumps(row, ensure_ascii=False),) for row in issues])
    return dict(Counter(row['reason'] for row in issues))


def ingest_community(builder, config, codex, english, add, issues, input_path):
    from datasources.community_registry import SOURCES
    by_title = defaultdict(set)
    for book in codex['books']:
        for owner in book['owners']:
            by_title[owner['title']].add(book['firstPageId'])
    books = {b['firstPageId']: b for b in codex['books']}
    for provider in BOOK_PROVIDERS:
        spec = SOURCES[provider].SPEC
        for entry in config.get(spec['source'], []):
            directory = input_path(entry['path'])
            manifest = json.loads(builder.read(directory / 'manifest.json'))
            if manifest['pin'] != entry['pin'] or manifest.get('source') != spec['source'] or not manifest.get('complete'):
                raise ValueError('Book community snapshot identity mismatch')
            for item in manifest['files']:
                target = (directory / item['file']).resolve()
                if not target.is_relative_to(directory) or hashlib.sha256(builder.read(target)).hexdigest() != item['sha256']:
                    raise ValueError('Book community snapshot input mismatch')
            archive_path = directory / 'archive.zip'
            raw = builder.read(archive_path)
            if hashlib.sha256(raw).hexdigest() != entry['pin']['sha256']:
                raise ValueError('Book community archive pin mismatch')
            provenance = {'source': spec['source'], 'sourceRevision': entry['pin'].get('revision') or entry['pin'].get('tag'),
                          **({'fileID': entry['pin']['fileID']} if 'fileID' in entry['pin'] else {})}
            flags = list(spec.get('flags', []))
            if provider in ('wow-lang', 'wow-forever-it', 'questtranslator-tr'):
                issues.append({'reason': 'contextOnlySource', 'source': spec['source'],
                               'detail': 'Existing unresolved data-license terms; no book text copied'})
                continue
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                paths = [name for name in archive.namelist() if name.endswith('.lua')]
                if provider in ('polish-forever', 'forever-tr', 'czech-forever'):
                    suffix = 'Data/Books.lua' if provider != 'czech-forever' else None
                    selected = [n for n in paths if n.endswith(suffix)] if suffix else [n for n in paths if re.search(r'/Data/Books\d+\.lua$', n)]
                    tables = {}
                    roots = [('PF', 'Text', 'Books')] if provider == 'polish-forever' else [('D', 'B')] if provider == 'forever-tr' else [('b',)]
                    for member in selected:
                        try:
                            for key, value in assignments(archive.read(member).decode('utf-8-sig'), roots):
                                rows = value.items() if len(key) == len(roots[0]) else [(key[-1], value)]
                                for fingerprint, text in rows:
                                    if fingerprint in tables and tables[fingerprint][0] != text:
                                        raise ValueError('Conflicting book hash translations')
                                    tables[fingerprint] = (text, member)
                        except ValueError as error:
                            issues.append({'reason': 'communityParseConflict', 'source': spec['source'], 'member': member, 'detail': str(error)})
                            tables = {}
                            break
                    hash_of = czech_key if provider == 'czech-forever' else turkish_key if provider == 'forever-tr' else lambda text: polish_hash(text.replace('\r', ''))
                    hashes = defaultdict(set)
                    for page, text in english.items():
                        hashes[hash_of(text)].add(text)
                    for page, context in english.items():
                        fingerprint = hash_of(context)
                        if len(hashes[fingerprint]) != 1 or fingerprint not in tables:
                            continue
                        text, member = tables[fingerprint]
                        if not isinstance(text, str):
                            issues.append({'reason': 'communityGenderVariants', 'source': spec['source'], 'pageId': page})
                            continue
                        add('bookpages', page, spec['locale'], 'description', text, spec['origin'],
                            {**provenance, 'member': member, 'matching': 'uniqueEnglishFingerprint',
                             'fingerprint': str(fingerprint)}, archive_path, context, flags)
                elif provider == 'classic-ua':
                    for member in [n for n in paths if n.endswith('entries/classic/object.lua') or n.endswith('entries/forever/object.lua')]:
                        for _, records in assignments(archive.read(member).decode('utf-8-sig'), [('object',)]):
                            if not isinstance(records, dict):
                                continue
                            for title, translated in records.items():
                                matches = by_title.get(title, set())
                                if len(matches) != 1 or not isinstance(translated, str):
                                    continue
                                first = next(iter(matches))
                                # Match the selected English book title, not an unrelated owner's alias.
                                if not any(o['title'] == title for o in books[first]['owners']):
                                    continue
                                add('books', first, 'ukUA', 'name', translated, spec['origin'],
                                    {**provenance, 'member': member, 'matching': 'uniqueOwnedEnglishTitle'},
                                    archive_path, title, flags)
                    for member in [n for n in paths if n.endswith('entries/classic/object_text.lua')]:
                        tables = list(assignments(archive.read(member).decode('utf-8-sig'), [('object_text',)]))
                        for _, records in tables:
                            for title, translated in records.items():
                                roots = by_title.get(title, set())
                                if len(roots) != 1:
                                    continue
                                book = books[next(iter(roots))]
                                if book['chainStatus'] != 'completeVanillaReference' or not isinstance(translated, dict):
                                    continue
                                page_texts = {k: v for k, v in translated.items() if isinstance(k, int)}
                                if len(page_texts) != len(book['pages']) or any(not isinstance(v, str) for v in page_texts.values()):
                                    issues.append({'reason': 'communityPageShapeMismatch', 'source': spec['source'], 'firstPageId': book['firstPageId']})
                                    continue
                                for index, page in enumerate(book['pages'], 1):
                                    if page['id'] in english:
                                        add('bookpages', page['id'], 'ukUA', 'description', page_texts[index],
                                            'ai' if translated.get('ai') else spec['origin'],
                                            {**provenance, 'member': member, 'matching': 'uniqueTitleAndCompleteChain',
                                             'pageOrdinal': index}, archive_path, english[page['id']], flags)
