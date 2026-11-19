"""Pin public book archives and expose their page evidence."""

import gzip
import hashlib
import json
import re

from datasources.common import ROOT, latest_revision, read_url


MIRROR = 'salty-max/wow-data'
CLASSIC = 'cmangos/classic-db'
WRATH = 'azerothcore/azerothcore-wotlk'
MIRROR_FILES = ('books-enUS', 'books-deDE', 'books-frFR', 'pages-enUS',
                'pages-deDE', 'pages-frFR', 'pages-esES', 'pages-esMX')
WRATH_FILES = ('page_text.sql', 'page_text_locale.sql')
SQL_TEXT = r"'((?:[^'\\]|\\.)*)'"


def fetch(output, pins=None):
    """Download only book inputs, using Git revisions and hashes for replay."""
    sources = {}
    for repo in (MIRROR, CLASSIC, WRATH):
        pin = (pins or {}).get(repo)
        revision = pin['revision'] if pin else latest_revision(f'https://github.com/{repo}.git')
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise ValueError('Invalid book archive revision')
        if repo == MIRROR:
            paths = [f'data/wowhead/forever/{name}.json' for name in MIRROR_FILES]
        elif repo == CLASSIC:
            if pin:
                paths = list(pin['files'])
            else:
                url = f'https://api.github.com/repos/{repo}/git/trees/{revision}?recursive=1'
                tree = json.loads(read_url(url, headers={'User-Agent': 'ForeverRosettaStone'}))
                if tree.get('sha') != revision or tree.get('truncated'):
                    raise ValueError('Incomplete CMaNGOS tree')
                paths = [row['path'] for row in tree['tree']
                         if re.fullmatch(r'Full_DB/ClassicDB_[\w]+\.sql\.gz', row['path'])]
            if len(paths) != 1 or not re.fullmatch(r'Full_DB/ClassicDB_[\w]+\.sql\.gz', paths[0]):
                raise ValueError('Expected one CMaNGOS Classic database')
        else:
            paths = [f'data/sql/base/db_world/{name}' for name in WRATH_FILES]
        directory = output / repo.split('/')[0]
        directory.mkdir(parents=True)
        files = {}
        for path in paths:
            raw = read_url(f'https://raw.githubusercontent.com/{repo}/{revision}/{path}')
            checksum = hashlib.sha256(raw).hexdigest()
            if pin and pin['files'].get(path) != checksum:
                raise ValueError('Pinned book archive changed: ' + path)
            (directory / path.rsplit('/', 1)[-1]).write_bytes(raw)
            files[path] = checksum
        if pin and set(files) != set(pin['files']):
            raise ValueError('Pinned book archive inventory changed')
        sources[repo] = {'revision': revision, 'files': files}
    return {'path': str(output.relative_to(ROOT)), 'pin': sources}


def inputs(entries, builder):
    """Read and hash the same pinned files on every offline rebuild."""
    for entry in entries:
        directory = (builder.root / entry['path']).resolve()
        if not directory.is_relative_to(builder.root / 'datasources/imports'):
            raise ValueError('Book archive outside datasources/imports')
        for repo, snapshot in entry['pin'].items():
            if repo not in (MIRROR, CLASSIC, WRATH) or not re.fullmatch(r'[0-9a-f]{40}', snapshot['revision']):
                raise ValueError('Invalid book archive pin')
            for upstream, digest in snapshot['files'].items():
                path = (directory / repo.split('/')[0] / upstream.rsplit('/', 1)[-1]).resolve()
                if not path.is_relative_to(directory):
                    raise ValueError('Unsafe book archive file')
                raw = builder.read(path)
                if hashlib.sha256(raw).hexdigest() != digest:
                    raise ValueError('Book archive input changed: ' + str(path))
                yield repo, snapshot['revision'], path, raw


def decode_mysql_text(raw):
    escapes = {'n': '\n', 'r': '\r', 't': '\t', '0': '\0', 'Z': '\x1a'}
    return re.sub(r'\\(.)', lambda match: escapes.get(match[1], match[1]), raw)


def classic_pages(repo, raw):
    if repo == CLASSIC:
        sql = (row.split(b' VALUES ', 1)[1].decode() for row in gzip.decompress(raw).splitlines()
               if row.startswith(b'INSERT INTO `page_text` VALUES '))
        pattern = r"\((\d+)," + SQL_TEXT + r",(\d+)\)"
    else:
        sql = [raw.decode()]
        pattern = r"(?m)^\((\d+)," + SQL_TEXT + r",(\d+),(?:NULL|-?\d+)\)"
    for fragment in sql:
        for identifier, text, next_page in re.findall(pattern, fragment):
            yield int(identifier), decode_mysql_text(text), int(next_page)


def wrath_locales(raw):
    pattern = r"(?m)^\((\d+),'([a-z]{2}[A-Z]{2})'," + SQL_TEXT + r",(?:NULL|-?\d+)\)"
    for identifier, locale, text in re.findall(pattern, raw.decode()):
        yield int(identifier), locale, decode_mysql_text(text)


def mirror_books(path, raw):
    """Both mirror formats key rendered pages by typed owner and reading order."""
    stem, locale = path.stem.split('-')
    document = json.loads(raw)
    if stem == 'books':
        for key, texts in document.items():
            if re.fullmatch(r'[io][1-9][0-9]*', key):
                yield ({'i': 'item', 'o': 'object'}[key[0]], int(key[1:])), locale, texts
    else:
        for kind in ('item', 'object'):
            for identifier, record in document.get({'item': 'itembook', 'object': 'objbook'}[kind], {}).items():
                yield (kind, int(identifier)), locale, record['pages']
