"""Fetch EG Link NPC and item caches; quests deliberately come from other sources."""

import json
import re

from datasources.common import ROOT, latest_revision, read_url, write_json

from datasources.wago.loader import parse_version


REPOSITORY = 'https://github.com/JIVESCORP/eg-link-output-wowf.git'


def fetch(output, revision=None):
    revision = revision or latest_revision(REPOSITORY)
    base = f'https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/{revision}/data'
    index = json.loads(read_url(base + '/index.json'))
    builds = index['products']['wowf']
    datasets = ('creature_details.enUS', 'item_hotfixes.enUS')
    output.mkdir(parents=True)
    write_json(output / 'index.json', index)
    entries = []

    for dataset in datasets:
        available = [build for build, names in builds.items() if dataset in names]

        if not available:
            raise ValueError('No EG Link snapshot for ' + dataset)

        build = max(available, key=parse_version)
        document = json.loads(read_url(f'{base}/wowf/{build}/{dataset}.json'))

        if document['meta']['clientBuild'] != build or document['meta']['locale'] != 'enUS':
            raise ValueError('EG Link build/locale differs from selected snapshot')

        path = output / (dataset + '.json')
        write_json(path, document)
        entries.append({'path': str(path.relative_to(ROOT)), 'revision': revision})

    write_json(output / 'source.json', {'repository': REPOSITORY, 'revision': revision})

    return entries


def fetch_book_objects(output, revision):
    """Retain all published Forever object-cache builds at the already selected revision."""
    if output.exists():
        raise ValueError('Use a new EG book snapshot directory')
    if not isinstance(revision, str) or not re.fullmatch(r'[a-f0-9]{40}', revision):
        raise ValueError('Expected a pinned EG Git revision')
    base = f'https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/{revision}/data'
    index = json.loads(read_url(base + '/index.json'))
    builds = index['products']['wowf']
    available = sorted((build for build, names in builds.items() if 'object_details.enUS' in names),
                       key=parse_version)
    if not available:
        raise ValueError('No EG Link book-object snapshots')
    output.mkdir(parents=True)
    write_json(output / 'index.json', index)
    entries = []
    for build in available:
        raw = read_url(f'{base}/wowf/{build}/object_details.enUS.json')
        document = json.loads(raw)
        meta = document['meta']
        if (meta.get('clientBuild') != build or meta.get('locale') != 'enUS'
                or meta.get('product') != 'wowf' or meta.get('dataset') != 'object_details'
                or meta.get('schemaVersion') != 1):
            raise ValueError('Unexpected EG book-object snapshot identity')
        target = output / build / 'object_details.enUS.json'
        target.parent.mkdir(parents=True)
        target.write_bytes(raw)
        entries.append({'path': str(target.relative_to(ROOT)), 'revision': revision,
                        'indexPath': str((output / 'index.json').relative_to(ROOT))})
    return entries


def fetch_book_texts(output, revision):
    """Retain native book captures; other sections of raw aggregated files are never indexed."""
    if output.exists() or not re.fullmatch(r'[a-f0-9]{40}', revision):
        raise ValueError('Use a new EG book-text directory and pinned revision')
    base = f'https://raw.githubusercontent.com/JIVESCORP/eg-link-output-wowf/{revision}/data'
    index = json.loads(read_url(base + '/index.json'))
    output.mkdir(parents=True)
    write_json(output / 'index.json', index)
    entries = []
    for build, datasets in sorted(index['products']['wowf'].items(), key=lambda row: parse_version(row[0])):
        for dataset in sorted(name for name in datasets if re.fullmatch(r'texts\.[a-z]{2}[A-Z]{2}', name)):
            raw = read_url(f'{base}/wowf/{build}/{dataset}.json')
            document = json.loads(raw)
            meta = document['meta']
            if (meta.get('product') != 'wowf' or meta.get('clientBuild') != build
                    or meta.get('dataset') != 'texts' or meta.get('locale') != dataset.split('.')[1]
                    or meta.get('schemaVersion') != 1):
                raise ValueError('Unexpected EG book-text identity')
            path = output / build / (dataset + '.json'); path.parent.mkdir(exist_ok=True)
            path.write_bytes(raw)
            entries.append({'path': str(path.relative_to(ROOT)), 'revision': revision})
    return entries
