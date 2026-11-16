"""Shared pinned GitHub snapshots for community translation datasources."""
import fnmatch
import hashlib
import io
import json
import re
from pathlib import Path, PurePosixPath
from urllib.parse import quote
from zipfile import ZipFile
from datasources.common import ROOT, read_url, write_json


def github_json(path):
    return json.loads(read_url('https://api.github.com/repos/' + path,
                               headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'ForeverRosettaStone'}))


def download(spec, pin=None):
    pin = pin or {}
    repo = spec['repository']
    if not isinstance(pin, dict) or pin and pin.get('repository') != repo:
        raise ValueError('Community pin repository mismatch')
    if spec.get('asset'):
        release = github_json(repo + '/releases/' + ('tags/' + quote(pin['tag'], safe='') if pin.get('tag') else 'latest'))
        if release.get('draft') or release.get('prerelease'):
            raise ValueError('Expected a published community release')
        assets = [asset for asset in release.get('assets', []) if asset['name'] == spec['asset']]
        if len(assets) != 1:
            raise ValueError('Expected exactly one text-only release asset')
        asset = assets[0]
        url = asset['browser_download_url']
        if not url.startswith(f'https://github.com/{repo}/releases/download/'):
            raise ValueError('Unexpected community release download host')
        identity = {'repository': repo, 'tag': release['tag_name'], 'assetID': asset['id']}
        if pin and identity['assetID'] != pin.get('assetID'):
            raise ValueError('Pinned community release asset changed')
    else:
        revision = pin.get('revision') or github_json(repo + '/commits/HEAD')['sha']
        if not re.fullmatch(r'[a-f0-9]{40}', revision):
            raise ValueError('Expected a full community commit SHA')
        identity = {'repository': repo, 'revision': revision}
        url = f'https://codeload.github.com/{repo}/zip/{revision}'
    raw = read_url(url)
    checksum = hashlib.sha256(raw).hexdigest()
    if pin and checksum != pin.get('sha256'):
        raise ValueError('Pinned community archive hash changed')
    return identity, url, raw


def fetch(spec, output, pin=None):
    if output.exists():
        raise ValueError('Use a new community snapshot directory')
    return write_snapshot(spec, output, *download(spec, pin))


def write_snapshot(spec, output, identity, url, raw):
    """Normalize a pinned archive collected from its upstream distribution service."""
    if output.exists():
        raise ValueError('Use a new community snapshot directory')
    checksum = hashlib.sha256(raw).hexdigest()
    output.mkdir(parents=True)
    (output / 'archive.zip').write_bytes(raw)
    inventory, records, lookups, names = [], [], [], set()
    size = 0
    with ZipFile(io.BytesIO(raw)) as archive:
        for item in sorted(archive.infolist(), key=lambda item: ('/forever/' in item.filename, item.filename)):
            path = PurePosixPath(item.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in item.filename or (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unsafe community archive path')
            if item.is_dir():
                continue
            relative = path if spec.get('preserveArchiveRoot') else PurePosixPath(*path.parts[1:])
            name = str(relative)
            data = any(fnmatch.fnmatchcase(name, pattern) for pattern in spec['files'])
            if not data and not re.search(r'(?i)license|copying|notice|readme', relative.name):
                continue
            size += item.file_size
            if size > spec.get('maxTextBytes', 64 * 1024 * 1024) or item.file_size > spec.get('maxFileBytes', 12 * 1024 * 1024) or name in names:
                raise ValueError('Invalid or oversized community text archive')
            names.add(name)
            content = archive.read(item)
            target = output / 'raw' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            inventory.append({'file': 'raw/' + name, 'sha256': hashlib.sha256(content).hexdigest()})
            if data:
                rows, references = spec['normalize'](name, content.decode('utf-8-sig'))
                for row in (*rows, *references):
                    row['sourceFile'] = 'raw/' + name
                    row.setdefault('flags', []).extend(spec.get('flags', []))
                records.extend(rows)
                lookups.extend(references)
    if not records and not lookups:
        raise ValueError('No supported community translations found')
    # Forever data overrides Classic fields. Conflicting variants in a layer remain explicit.
    grouped = {}
    for row in records:
        key, layer = (row.get('locale'), row['kind'], row['id'], row['field']), int('/forever/' in row['sourceFile'])
        previous = grouped.get(key)
        if previous is None or layer > previous[0]:
            grouped[key] = (layer, [row])
        elif layer == previous[0] and row['text'] not in {candidate['text'] for candidate in previous[1]}:
            previous[1].append(row)
    records = []
    for _, rows in grouped.values():
        if len(rows) > 1:
            for row in rows:
                row.setdefault('flags', []).append('upstreamConflictingVariants')
        records.extend(rows)
    identity['sha256'] = checksum
    write_json(output / 'upstream.json', {**identity, 'url': url})
    write_json(output / 'records.json', {'records': records, 'lookups': lookups})
    (output / 'SOURCE.md').write_bytes(Path(spec['notice']).read_bytes())
    for name in ('archive.zip', 'upstream.json', 'records.json', 'SOURCE.md'):
        inventory.append({'file': name, 'sha256': hashlib.sha256((output / name).read_bytes()).hexdigest()})
    write_json(output / 'manifest.json', {'schemaVersion': 1, 'complete': True, 'source': spec['source'],
               'locale': spec.get('locale'), 'locales': spec.get('locales') or [spec['locale']], 'origin': spec['origin'], 'pin': identity, 'files': inventory})
    return {'path': str(output.relative_to(ROOT)), 'source': spec['source'], 'pin': identity}


def fields(kind, entity_id, value, mapping, origin=None, english=None):
    if type(entity_id) is not int or entity_id <= 0:
        return []
    rows = []
    for key, field in mapping.items():
        text = value.get(key) if isinstance(value, dict) else value if key is None else None
        variants = {text} if isinstance(text, str) else {v for v in text.values() if isinstance(v, str)} if isinstance(text, dict) else set()
        for translated in sorted(variants):
            if not translated.strip():
                continue
            flags = ['upstreamGenderVariants'] if len(variants) > 1 else []
            if re.search(r'(?<!\$)\{[^{}]+\}|@\[|@<|\[\[', translated):
                flags.append('upstreamMarkup:reviewBeforeReuse')
            rows.append({'kind': kind, 'id': str(entity_id), 'field': field, 'text': translated, 'flags': flags,
                         **({'origin': origin} if origin else {}),
                         **({'english': english[field]} if english and english.get(field) else {})})
    return rows


def polish_hash(text):
    data, value = text.encode(), 1
    if not data:
        return 0
    for index in range(0, len(data), 3):
        missing = len(data) - index - 1 + 256
        value = value * 8161 % 4294967279 + data[index] * 16776193
        value += (data[index + 1] if index + 1 < len(data) else missing) * 8372226
        value += (data[index + 2] if index + 2 < len(data) else missing) * 3932164
    return value % 4294967291
