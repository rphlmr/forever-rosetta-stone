"""Fetch pinned catalog sources, then build and verify their SQLite reference corpus."""

import argparse
import hashlib
import json
import signal
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from datasources.blizzard import loader as blizzard
from datasources.books import archives as book_archives
from datasources.eg_link import loader as eg_link
from datasources.questie import loader as questie
from datasources.wago import loader as wago
from datasources.vmangos import loader as vmangos
from datasources.common import ROOT, write_json

sys.path.insert(0, str(ROOT))
from datasources.corpus.translation_corpus import build, open_corpus, verify


from datasources.community_registry import SOURCES as COMMUNITY_SOURCES
BOOK_ONLY_PROVIDERS = {'vmangos', 'book-archives'}
PROVIDERS = ('wago', 'questie', 'blizzard', 'eg-link', 'vmangos', 'book-archives', *COMMUNITY_SOURCES)
DEFAULT_PROVIDERS = tuple(provider for provider in PROVIDERS if provider not in BOOK_ONLY_PROVIDERS)
SOURCE_KEYS = {'wago': ('wago', 'talents'), 'questie': ('questie',),
               'blizzard': ('blizzard',), 'eg-link': ('egLink', 'egBooks', 'egBookTexts'), 'vmangos': ('vmangos',),
               'book-archives': ('bookArchives',)}
PIN_KEYS = {'wago': 'wagoBuild', 'questie': 'questieRevision',
            'blizzard': 'blizzardNamespace', 'eg-link': 'egLinkRevision', 'vmangos': 'vmangos',
            'book-archives': 'bookArchives'}
SOURCE_KEYS.update({name: (module.SPEC['source'],) for name, module in COMMUNITY_SOURCES.items()})
PIN_KEYS.update({name: module.SPEC['source'] for name, module in COMMUNITY_SOURCES.items()})


def reuse_sources(previous, selected, book_scope=None):
    """Reuse only verified raw inputs from an explicitly selected completed run."""
    from datasources.books.texts import BOOK_PROVIDERS

    previous = previous.resolve()
    if not previous.is_relative_to(ROOT / 'datasources/imports'):
        raise ValueError('--reuse must name a completed run under datasources/imports/')
    if not (previous / 'corpus.sqlite').is_file():
        raise ValueError('Cannot reuse a run without its verified corpus.sqlite')
    complete = json.loads((previous / 'complete.json').read_text())
    if complete.get('verified') is not True:
        raise ValueError('Cannot reuse an unverified run')
    connection = open_corpus(previous / 'corpus.sqlite')
    try:
        hashes = dict(connection.execute('SELECT path,sha256 FROM inputs'))
    finally:
        connection.close()

    def check_file(path):
        relative = str(path.relative_to(ROOT))
        if hashes.get(relative) != hashlib.sha256(path.read_bytes()).hexdigest():
            raise ValueError('Reused source input changed: ' + relative)

    check_file(previous / 'sources.json')
    sources = json.loads((previous / 'sources.json').read_text())
    pins = json.loads((previous / 'pins.json').read_text())
    retained, retained_pins = {}, {}
    providers = DEFAULT_PROVIDERS
    if book_scope:
        providers = ('vmangos', 'wago', 'eg-link')
        if book_scope == 'book-texts':
            providers += ('book-archives', *BOOK_PROVIDERS)
    for provider in providers:
        # A selected Blizzard refresh can conditionally reuse its previous raw responses.
        if provider in selected and provider != 'blizzard':
            continue
        for key in SOURCE_KEYS[provider]:
            if ((book_scope is None and key in ('egBooks', 'egBookTexts'))
                    or (book_scope == 'book-identities' and key == 'egBookTexts')
                    or (book_scope is not None and key in ('egLink', 'talents'))):
                continue
            entries = sources.get(key, [])
            for entry in entries:
                path = (ROOT / (entry if isinstance(entry, str) else entry['path'])).resolve()
                if not path.is_relative_to(ROOT / 'datasources/imports') or not path.exists():
                    raise ValueError('Missing or invalid reused source: ' + str(path))
                relative = str(path.relative_to(ROOT))
                inputs = [ROOT / name for name in hashes
                          if name == relative or name.startswith(relative + '/')]
                if not inputs:
                    raise ValueError('Reused source has no verified inputs: ' + relative)
                for source_file in inputs:
                    check_file(source_file)
                if isinstance(entry, dict) and entry.get('indexPath'):
                    index_path = (ROOT / entry['indexPath']).resolve()
                    if not index_path.is_relative_to(ROOT / 'datasources/imports'):
                        raise ValueError('Invalid reused book index path')
                    check_file(index_path)
            if provider not in selected:
                retained[key] = entries
        if any(retained.get(key) for key in SOURCE_KEYS[provider]):
            retained_pins[PIN_KEYS[provider]] = pins[PIN_KEYS[provider]]
    return retained, retained_pins


def refresh(output, env_file, pins=None, sources=None, reuse=None, wago_tables=None, wago_locales=None, book_codex_only=False, book_texts=False):
    """Fetch selected providers and publish a verified corpus with explicit source provenance."""
    from datasources.books.texts import BOOK_PROVIDERS
    book_mode = book_codex_only or book_texts
    book_scope = 'book-texts' if book_texts else 'book-identities' if book_codex_only else None
    output = output.resolve()
    if not output.is_relative_to(ROOT / 'datasources/imports') or output.exists():
        raise ValueError('Use a new refresh directory under datasources/imports/')
    selected = set(('vmangos', 'wago', 'eg-link', *(('book-archives', *BOOK_PROVIDERS) if book_texts else ())) if book_mode and sources is None
                   else DEFAULT_PROVIDERS if sources is None else sources)
    if not selected or selected - set(PROVIDERS):
        raise ValueError('Select one or more known sources: ' + ', '.join(PROVIDERS))
    if book_mode:
        if selected - {'vmangos', 'wago', 'eg-link', *(('book-archives', *BOOK_PROVIDERS) if book_texts else ())}:
            raise ValueError('Selected sources are outside the requested book scope')
        if wago_tables not in (None, ['ItemSparse']) or wago_locales not in (None, ['enUS']) and not book_texts:
            raise ValueError('Book-only refresh uses ItemSparse enUS')
        wago_tables, wago_locales = ['ItemSparse'], list(wago.LOCALES) if book_texts else ['enUS']
    elif selected & BOOK_ONLY_PROVIDERS:
        raise ValueError('Select --book-texts or --book-codex-only for book sources')
    values = blizzard.credentials(env_file) if 'blizzard' in selected else None
    template = json.loads((ROOT / 'datasources/corpus/sources.json').read_text())
    config = {**template, **{key: [] for keys in SOURCE_KEYS.values() for key in keys}}
    resolved_pins = {}
    if reuse is not None:
        retained, resolved_pins = reuse_sources(reuse, selected, book_scope)
        config.update(retained)
    if book_mode:
        config = {**{key: [] for keys in SOURCE_KEYS.values() for key in keys},
                  **{key: config[key] for key in ('vmangos', 'wago', 'egBooks', 'egBookTexts', 'bookArchives',
                     *([COMMUNITY_SOURCES[name].SPEC['source'] for name in BOOK_PROVIDERS] if book_texts else [])) if key in config},
                  'scope': book_scope,
                  'limitations': [('Existing source book texts; no authored translations or UI.' if book_texts
                                   else 'Identity-only codex. No book bodies or translations are imported.'),
                                  'Vanilla page links are not verified Forever page sequences.']}
    reused = [name for name in PROVIDERS if name not in selected
              and any(config[key] for key in SOURCE_KEYS[name])]
    pins = pins or {}
    relative = str(output.relative_to(ROOT))
    output.mkdir(parents=True)
    print('Fetching: ' + ', '.join(sorted(selected)), flush=True)
    # Resolve community archives before spending the core providers' collection budget.
    for name in sorted(selected & COMMUNITY_SOURCES.keys()):
        print('Fetching community: ' + name, flush=True)
        entry = COMMUNITY_SOURCES[name].fetch(output / name, pins.get(PIN_KEYS[name]))
        config[SOURCE_KEYS[name][0]] = [entry]
        resolved_pins[PIN_KEYS[name]] = entry['pin']
    if 'vmangos' in selected:
        entry = vmangos.fetch(output / 'vmangos', pins.get('vmangos'))
        config['vmangos'] = [entry]
        resolved_pins['vmangos'] = entry['pin']
    if 'book-archives' in selected:
        entry = book_archives.fetch(output / 'book-archives', pins.get('bookArchives'))
        config['bookArchives'] = [entry]
        resolved_pins['bookArchives'] = entry['pin']
    with ThreadPoolExecutor(max_workers=2) as pool:
        if wago_tables or wago_locales:
            wago_future = pool.submit(wago.fetch, output / 'wago', pins.get('wagoBuild'),
                                     wago_tables, wago_locales) if 'wago' in selected else None
        else:
            wago_future = pool.submit(wago.fetch, output / 'wago', pins.get('wagoBuild')) if 'wago' in selected else None
        if 'eg-link' in selected and book_mode:
            eg_revision = pins.get('egLinkRevision') or eg_link.latest_revision(eg_link.REPOSITORY)
            eg_future = pool.submit(eg_link.fetch_book_objects, output / 'eg-link-books', eg_revision)
        else:
            eg_future = pool.submit(eg_link.fetch, output / 'eg-link', pins.get('egLinkRevision')) if 'eg-link' in selected else None
        if 'questie' in selected:
            source = questie.fetch(output / 'questie', pins.get('questieRevision'))
            config['questie'] = [source]
            resolved_pins['questieRevision'] = source['revision']
        if 'blizzard' in selected:
            extra_ids = set()
            for entry in config['questie']:
                extra_ids.update(questie.quest_ids(ROOT / entry['path']))
            previous_blizzard = []
            if reuse is not None:
                previous_blizzard = json.loads((reuse / 'sources.json').read_text()).get('blizzard', [])
            cache_options = {'previous': ROOT / previous_blizzard[0]['path']} if previous_blizzard else {}
            namespace = blizzard.fetch(output / 'blizzard', values, extra_ids,
                                       pins.get('blizzardNamespace'), **cache_options)
            config['blizzard'] = [{'path': relative + '/blizzard'}]
            resolved_pins['blizzardNamespace'] = namespace
        if wago_future is not None:
            resolved_pins['wagoBuild'] = wago_future.result()
            config['wago'] = [relative + '/wago']
            config['talents'] = [relative + '/wago'] if not wago_tables or 'Talent' in wago_tables else []
        if eg_future is not None and book_mode:
            config['egBooks'] = eg_future.result()
            resolved_pins['egLinkRevision'] = eg_revision
            if book_texts:
                config['egBookTexts'] = eg_link.fetch_book_texts(output / 'eg-book-texts', eg_revision)
        elif eg_future is not None:
            config['egLink'] = eg_future.result()
            resolved_pins['egLinkRevision'] = config['egLink'][0]['revision']
    write_json(output / 'sources.json', config)
    write_json(output / 'pins.json', resolved_pins)
    print('All selected fetches complete; building SQLite', flush=True)
    database = output / 'corpus.sqlite'
    build(ROOT, output / 'sources.json', database)
    connection = open_corpus(database)
    try:
        result = verify(connection, ROOT)
        if result['valid'] and (config.get('vmangos') or config.get('egBooks')):
            from datasources.books.codex import export
            write_json(output / 'book-codex.json', export(connection))
    finally:
        connection.close()
    if not result['valid']:
        database.unlink()
        raise ValueError('Corpus input verification failed: ' + ', '.join(result['changedInputs']))
    write_json(output / 'complete.json', {
        'database': str(database.relative_to(ROOT)), 'verified': True,
        'fetchedSources': sorted(selected), 'reusedSources': reused,
        'reuseRun': str(reuse.resolve().relative_to(ROOT)) if reuse is not None else None,
    })
    return database


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'datasources/imports' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    parser.add_argument('--env-file', type=Path, default=ROOT / '.env')
    parser.add_argument('--pins', type=Path, help='Replay selected revisions/build/namespace from an earlier pins.json')
    parser.add_argument('--sources', nargs='+', choices=PROVIDERS, help='Fetch only these providers in the selected scope')
    parser.add_argument('--reuse', type=Path, help='Keep unselected providers from this completed run')
    parser.add_argument('--book-texts', action='store_true', help='Collect existing book texts and translations for the codex; no UI')
    parser.add_argument('--book-codex-only', action='store_true', help='Build only readable identities; no catalog scan or page text import')
    parser.add_argument('--wago-tables', nargs='+', choices=wago.SUPPORTED_TABLES)
    parser.add_argument('--wago-locales', nargs='+', choices=wago.LOCALES)
    args = parser.parse_args()
    signal.alarm(3600)

    try:
        pins = json.loads(args.pins.read_text()) if args.pins else None
        print(refresh(args.output, args.env_file, pins, sources=args.sources, reuse=args.reuse,
                      wago_tables=args.wago_tables, wago_locales=args.wago_locales, book_codex_only=args.book_codex_only, book_texts=args.book_texts))
    finally:
        signal.alarm(0)


if __name__ == '__main__':
    main()
