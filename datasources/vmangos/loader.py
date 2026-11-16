"""Pin VMaNGOS's SQLite distribution and extract book identities, never page text."""
import hashlib
import io
import json
import re
import sqlite3
import zipfile
from pathlib import Path

from datasources.common import ROOT, read_url, write_json

REPOSITORY = 'vmangos/core'
PATCH = 10


def identities(database):
    """Use the latest template row at Vanilla 1.12 (content patch 10)."""
    connection = sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    try:
        if connection.execute('PRAGMA quick_check').fetchall()[0][0] != 'ok':
            raise ValueError('Invalid VMaNGOS SQLite snapshot')
        owners = []
        for kind, table in (('item', 'item_template'), ('object', 'gameobject_template')):
            columns = 't.entry,t.patch,t.name,t.page_text' if kind == 'item' else 't.entry,t.patch,t.name,t.type,t.data0,t.data7'
            rows = connection.execute(f'''SELECT {columns} FROM {table} t WHERE t.patch =
                (SELECT MAX(s.patch) FROM {table} s WHERE s.entry=t.entry AND s.patch<=?)''', (PATCH,))
            for row in rows:
                first = row['page_text'] if kind == 'item' else (
                    row['data0'] if row['type'] == 9 else row['data7'] if row['type'] == 10 else 0)
                if first > 0:
                    owners.append({'kind': kind, 'id': row['entry'], 'title': row['name'],
                                   'firstPageId': first, 'patch': row['patch']})
        # No body text or localized fields enter this projection.
        pages = [{'id': row[0], 'nextPageId': row[1]} for row in connection.execute(
            'SELECT entry,next_page FROM page_text ORDER BY entry')]
        return {'schemaVersion': 1, 'patch': PATCH,
                'owners': sorted(owners, key=lambda row: (row['kind'], row['id'])), 'pages': pages}
    finally:
        connection.close()


def fetch(output, pin=None):
    if output.exists():
        raise ValueError('Use a new VMaNGOS snapshot directory')
    headers = {'User-Agent': 'ForeverRosettaStone', 'Accept': 'application/vnd.github+json'}
    if pin is not None and (pin.get('repository') != REPOSITORY or not isinstance(pin.get('assetID'), int)):
        raise ValueError('Invalid VMaNGOS replay pin')
    release_raw = read_url('https://api.github.com/repos/vmangos/core/releases/tags/db_latest', headers)
    release = json.loads(release_raw)
    if pin:
        asset_raw = read_url(f'https://api.github.com/repos/vmangos/core/releases/assets/{pin["assetID"]}', headers)
        asset = json.loads(asset_raw)
    else:
        assets = [row for row in release['assets'] if re.fullmatch(r'db-sqlite-[0-9a-f]+\.zip', row['name'])]
        if len(assets) != 1:
            raise ValueError('Expected one VMaNGOS SQLite asset')
        asset = assets[0]
        asset_raw = json.dumps(asset).encode()
    if not re.fullmatch(r'db-sqlite-[0-9a-f]+\.zip', asset['name']):
        raise ValueError('Unexpected VMaNGOS asset name')
    url = asset['browser_download_url']
    if not url.startswith('https://github.com/vmangos/core/releases/download/'):
        raise ValueError('Unexpected VMaNGOS download host')
    raw = read_url(url)
    checksum = hashlib.sha256(raw).hexdigest()
    if asset.get('digest') != 'sha256:' + checksum or (pin and pin.get('sha256') != checksum):
        raise ValueError('VMaNGOS archive hash mismatch')
    identity = {'repository': REPOSITORY, 'assetID': asset['id'], 'assetName': asset['name'],
                'sha256': checksum, 'patch': PATCH}
    if pin and identity != pin:
        raise ValueError('VMaNGOS replay asset identity changed')
    output.mkdir(parents=True)
    (output / 'archive.zip').write_bytes(raw)
    (output / 'release.json').write_bytes(release_raw)
    (output / 'asset.json').write_bytes(asset_raw)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names = [row for row in archive.infolist() if row.filename == 'sqlite-dump/mangos.sqlite']
        if len(names) != 1 or names[0].file_size > 512 * 1024 * 1024:
            raise ValueError('Invalid VMaNGOS world database archive')
        (output / 'mangos.sqlite').write_bytes(archive.read(names[0]))
    write_json(output / 'identities.json', identities(output / 'mangos.sqlite'))
    (output / 'SOURCE.md').write_bytes(Path(__file__).with_name('SOURCE.md').read_bytes())
    files = [{'file': name, 'sha256': hashlib.sha256((output / name).read_bytes()).hexdigest()}
             for name in ('archive.zip', 'release.json', 'asset.json', 'mangos.sqlite', 'identities.json', 'SOURCE.md')]
    write_json(output / 'manifest.json', {'schemaVersion': 1, 'complete': True, 'pin': identity, 'files': files})
    return {'path': str(output.relative_to(ROOT)), 'pin': identity}
