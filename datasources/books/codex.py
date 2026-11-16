"""Reconcile source-backed readable identities without importing body text or translations."""
import csv
import hashlib
import io
import json
from collections import Counter
from pathlib import Path

from datasources.wago.loader import parse_version


def positive(value, allow_zero=False):
    if isinstance(value, bool):
        raise ValueError('Boolean is not a book/page ID')
    number = int(value)
    if str(number) != str(value) or number < (0 if allow_zero else 1):
        raise ValueError('Invalid book/page ID: ' + str(value))
    return number


def reconcile(root, config, read):
    """read() registers every raw input in the corpus input-hash inventory."""
    root = Path(root).resolve()
    candidates, links = {}, {}

    def path(value):
        result = (root / value).resolve()
        if not result.is_relative_to(root / 'datasources/imports'):
            raise ValueError('Book evidence must stay under datasources/imports/')
        return result

    def observe(kind, identifier, title, first, evidence):
        if kind not in ('item', 'object') or not isinstance(title, str) or not title.strip():
            raise ValueError('Invalid readable owner')
        key = (kind, positive(identifier))
        first = positive(first, allow_zero=True)
        candidates.setdefault(key, []).append({'title': title, 'firstPageId': first, **evidence})

    for entry in config.get('vmangos', []):
        directory = path(entry['path'])
        manifest = json.loads(read(directory / 'manifest.json'))
        if manifest.get('schemaVersion') != 1 or manifest.get('complete') is not True or manifest['pin'] != entry['pin']:
            raise ValueError('VMaNGOS snapshot identity mismatch')
        if entry['pin'].get('repository') != 'vmangos/core' or entry['pin'].get('patch') != 10:
            raise ValueError('Unsupported VMaNGOS identity/patch')
        inventory = set()
        for item in manifest['files']:
            target = (directory / item['file']).resolve()
            if not target.is_relative_to(directory) or item['file'] in inventory:
                raise ValueError('Invalid VMaNGOS input path')
            inventory.add(item['file'])
            if hashlib.sha256(read(target)).hexdigest() != item['sha256']:
                raise ValueError('VMaNGOS snapshot hash mismatch')
        if not {'archive.zip', 'asset.json', 'release.json', 'mangos.sqlite', 'identities.json', 'SOURCE.md'} <= inventory:
            raise ValueError('Incomplete VMaNGOS snapshot')
        archive = next(item for item in manifest['files'] if item['file'] == 'archive.zip')
        if archive['sha256'] != entry['pin']['sha256']:
            raise ValueError('VMaNGOS archive differs from replay pin')
        document = json.loads(read(directory / 'identities.json'))
        if document.get('schemaVersion') != 1 or document.get('patch') != 10:
            raise ValueError('Unsupported VMaNGOS projection')
        evidence = {'source': 'vmangos', 'assetID': entry['pin']['assetID'], 'patch': 10,
                    'path': str((directory / 'identities.json').relative_to(root))}
        seen = set()
        for owner in document['owners']:
            key = (owner['kind'], owner['id'])
            if key in seen:
                raise ValueError('Duplicate VMaNGOS owner')
            seen.add(key)
            observe(owner['kind'], owner['id'], owner['title'], owner['firstPageId'], evidence)
        for page in document['pages']:
            identifier = positive(page['id'])
            if identifier in links:
                raise ValueError('Duplicate VMaNGOS page')
            links[identifier] = {'nextPageId': positive(page['nextPageId'], allow_zero=True), **evidence}

    wago_builds = set()
    for directory in config.get('wago', []):
        directory = path(directory)
        manifest = json.loads(read(directory / 'manifest.json'))
        for item in manifest['results']:
            if item['table'] != 'ItemSparse' or item['locale'] != 'enUS' or item.get('status') not in ('downloaded', 'existing'):
                continue
            wago_builds.add(manifest['build'])
            if len(wago_builds) > 1:
                raise ValueError('Do not mix Wago builds in a book codex')
            parse_version(manifest['build'])
            target = (directory / item['file']).resolve()
            if not target.is_relative_to(directory):
                raise ValueError('Invalid Wago book input path')
            raw = read(target)
            if hashlib.sha256(raw).hexdigest() != item['sha256']:
                raise ValueError('Wago book snapshot hash mismatch')
            rows = csv.DictReader(io.StringIO(raw.decode('utf-8-sig')))
            if not {'ID', 'Display_lang', 'PageID'} <= set(rows.fieldnames or []):
                raise ValueError('ItemSparse lacks book identity fields')
            seen = set()
            for row in rows:
                identifier = positive(row['ID'])
                if identifier in seen:
                    raise ValueError('Duplicate Wago item')
                seen.add(identifier)
                first = positive(row['PageID'], allow_zero=True)
                # Include zero-page overrides for owners VMaNGOS considers readable.
                if first or ('item', identifier) in candidates:
                    observe('item', identifier, row['Display_lang'], first,
                            {'source': 'wago', 'build': manifest['build'], 'path': str(target.relative_to(root))})

    # Sparse cache exports are observations, not complete build inventories. Keep each
    # object's newest observation, including one that says it no longer opens a page.
    newest = {}
    for entry in config.get('egBooks', []):
        target = path(entry['path'])
        document = json.loads(read(target))
        meta = document['meta']
        if (meta.get('product') != 'wowf' or meta.get('dataset') != 'object_details'
                or meta.get('locale') != 'enUS' or meta.get('schemaVersion') != 1):
            raise ValueError('Unsupported EG book object snapshot')
        version = parse_version(meta['clientBuild'])
        if entry.get('indexPath'):
            index = json.loads(read(path(entry['indexPath'])))
            if 'object_details.enUS' not in index['products']['wowf'].get(meta['clientBuild'], {}):
                raise ValueError('EG book snapshot absent from pinned index')
        evidence = {'source': 'egLink', 'build': meta['clientBuild'], 'revision': entry['revision'],
                    'path': str(target.relative_to(root)), 'license': meta['license'],
                    'attribution': meta['attribution']}
        for identifier, row in document['objects'].items():
            identifier = positive(identifier)
            prior = newest.get(identifier)
            if prior and version == prior[0] and row != prior[1]:
                raise ValueError('Conflicting EG object observations in the same build')
            if not prior or version > prior[0]:
                newest[identifier] = (version, row, evidence)
    for identifier, (_, row, evidence) in sorted(newest.items()):
        index = 0 if row['type'] == 9 else 7 if row['type'] == 10 else None
        first = row['data'][index] if index is not None else 0
        if first or ('object', identifier) in candidates:
            observe('object', identifier, row['name'], first, evidence)

    books, excluded = {}, []
    for (kind, identifier), observations in sorted(candidates.items()):
        # Each owner has one Vanilla candidate and at most one selected Forever observation.
        selected = observations[-1]
        flags = []
        if len({row['firstPageId'] for row in observations}) > 1:
            flags.append('firstPageConflict')
        if len({row['title'] for row in observations}) > 1:
            flags.append('titleConflict')
        owner = {'kind': kind, 'id': identifier, 'title': selected['title'],
                 'firstPageId': selected['firstPageId'], 'selectedSource': selected['source'],
                 'status': {'vmangos': 'vanillaCandidate', 'wago': 'foreverClient',
                            'egLink': 'foreverObserved'}[selected['source']],
                 'observations': observations, 'flags': flags}
        if not selected['firstPageId']:
            excluded.append(owner)
            continue
        first = selected['firstPageId']
        books.setdefault(first, {'firstPageId': first, 'owners': []})['owners'].append(owner)

    page_uses = {}
    for first, book in sorted(books.items()):
        chain, seen, current = [], set(), first
        issues = []
        while current:
            if current in seen:
                issues.append({'type': 'cycle', 'pageId': current})
                break
            if current not in links:
                issues.append({'type': 'missingPage', 'pageId': current})
                break
            seen.add(current)
            chain.append({'id': current, **links[current]})
            page_uses.setdefault(current, []).append(first)
            current = links[current]['nextPageId']
        # A complete Vanilla chain is still not a verified Forever page sequence.
        book.update(titles=sorted({o['title'] for o in book['owners']}), pages=chain, chainStatus='incomplete' if issues else 'completeVanillaReference',
                    issues=issues, foreverPageSequenceVerified=False)
    for page, firsts in page_uses.items():
        if len(firsts) > 1:
            for first in firsts:
                books[first]['issues'].append({'type': 'sharedPage', 'pageId': page, 'firstPageIds': sorted(firsts)})
    owners = [owner for book in books.values() for owner in book['owners']]
    summary = {'books': len(books), 'owners': len(owners), 'pages': len(page_uses),
               'ownerStatus': dict(sorted(Counter(o['status'] for o in owners).items())),
               'ownersWithConflicts': sum(bool(o['flags']) for o in owners),
               'incompleteChains': sum(b['chainStatus'] == 'incomplete' for b in books.values()),
               'excludedOwners': len(excluded)}
    return {'schemaVersion': 1, 'scope': 'identity-only', 'summary': summary,
            'books': [books[key] for key in sorted(books)], 'excludedOwners': excluded}


def store(connection, document):
    connection.execute('CREATE TABLE book_codex (first_page_id INTEGER PRIMARY KEY, document TEXT NOT NULL)')
    connection.execute('CREATE TABLE book_codex_metadata (document TEXT NOT NULL)')
    connection.executemany('INSERT INTO book_codex VALUES (?,?)',
                          [(b['firstPageId'], json.dumps(b, ensure_ascii=False, sort_keys=True)) for b in document['books']])
    connection.execute('INSERT INTO book_codex_metadata VALUES (?)',
                       (json.dumps({k: v for k, v in document.items() if k != 'books'}, ensure_ascii=False, sort_keys=True),))


def export(connection):
    document = json.loads(connection.execute('SELECT document FROM book_codex_metadata').fetchone()[0])
    document['books'] = [json.loads(row[0]) for row in connection.execute('SELECT document FROM book_codex ORDER BY first_page_id')]
    return document


def main():
    import argparse
    from datasources.common import ROOT, write_json
    from datasources.corpus.translation_corpus import open_corpus, verify
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    target = args.output.resolve()
    if not target.is_relative_to(ROOT / 'datasources/imports') or target.exists():
        parser.error('Use a new output path under datasources/imports/')
    connection = open_corpus(args.database)
    try:
        result = verify(connection, ROOT)
        if not result['valid']:
            raise ValueError('Codex source inputs changed: ' + ', '.join(result['changedInputs']))
        write_json(target, export(connection))
    finally:
        connection.close()
    print(target)


if __name__ == '__main__':
    main()
