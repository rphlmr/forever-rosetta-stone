"""Discover public CurseForge releases and download pinned archives without API credentials."""

from datetime import datetime
import hashlib
import json
import re
from urllib.parse import quote

from datasources.common import read_url

# CurseForge's public website identifies WoW Forever with this flavor type.
FOREVER_FLAVOR = 88568


def archive_identity(spec, file):
    project_id, file_id = spec['projectID'], file.get('id')
    name = file.get('fileName') or ''
    match = re.fullmatch(spec['archivePattern'], name) if isinstance(name, str) else None
    if (type(file_id) is not int or file_id <= 0 or file.get('projectId') != project_id
            or not match or file.get('releaseType') != 1 or file.get('status') != 4
            or FOREVER_FLAVOR not in file.get('gameVersionTypeIds', [])
            or file.get('isEarlyAccessContent') is True):
        raise ValueError('Expected an approved public Forever text archive for the configured CurseForge project')
    return {'distribution': 'curseforge', 'projectID': project_id, 'fileID': file_id,
            'fileName': name, 'tag': match.group(1)}


def latest(spec):
    """Read the website's paginated file listing afresh; never fall back to a saved file ID."""
    candidates, seen = [], set()
    for page in range(200):
        url = (f"https://www.curseforge.com/api/v1/mods/{spec['projectID']}/files"
               f'?pageIndex={page}&pageSize=50&sort=dateCreated&sortDescending=true')
        response = json.loads(read_url(url, headers={'User-Agent': 'ForeverRosettaStone source updater',
                                                   'Accept': 'application/json'}))
        rows, pagination = response['data'], response['pagination']
        if (not isinstance(rows, list) or pagination['index'] != page
                or pagination['pageSize'] != 50 or type(pagination['totalCount']) is not int):
            raise ValueError('Unexpected CurseForge file pagination')
        for row in rows:
            if row.get('id') in seen:
                raise ValueError('CurseForge file listing changed during discovery; run refresh again')
            seen.add(row.get('id'))
            try:
                identity = archive_identity(spec, row)
            except ValueError:
                continue
            date = datetime.fromisoformat(row['dateCreated'].replace('Z', '+00:00'))
            if date.tzinfo is None:
                raise ValueError('CurseForge file date must include a timezone')
            candidates.append((date, identity['fileID'], {**identity, 'fileDate': row['dateCreated'],
                                                        'discoveryURL': url, 'fileLength': row['fileLength']}))
        if (page + 1) * 50 >= pagination['totalCount']:
            break
        if len(rows) != 50:
            raise ValueError('Incomplete CurseForge file listing')
    else:
        raise ValueError('CurseForge file discovery exceeds the page limit')
    if not candidates:
        raise ValueError('No approved public Forever text release found on CurseForge')
    return max(candidates, key=lambda candidate: candidate[:2])[2]


def download(spec, pin=None):
    if pin is None:
        identity = latest(spec)
    else:
        if not isinstance(pin, dict) or pin.get('projectID') != spec['projectID']:
            raise ValueError('CurseForge pin project mismatch')
        identity = archive_identity(spec, {'projectId': pin['projectID'], 'id': pin.get('fileID'),
            'fileName': pin.get('fileName'), 'releaseType': 1, 'status': 4,
            'gameVersionTypeIds': [FOREVER_FLAVOR]})
        identity.update({key: pin[key] for key in ('fileDate', 'discoveryURL', 'fileLength') if key in pin})
    file_id = identity['fileID']
    url = f"https://edge.forgecdn.net/files/{file_id // 1000}/{file_id % 1000}/{quote(identity['fileName'], safe='')}"
    raw = read_url(url)
    if 'fileLength' in identity and len(raw) != identity['fileLength']:
        raise ValueError('CurseForge archive length mismatch')
    checksum = hashlib.sha256(raw).hexdigest()
    if pin and pin.get('sha256') and checksum != pin['sha256']:
        raise ValueError('Pinned CurseForge archive hash changed')
    return identity, url, raw
