"""Collect unfiltered, multilingual Forever quest API responses with an app token."""

import base64
import hashlib
import json
import re
import ssl
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from threading import Lock
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse

from datasources.common import read_url, read_url_response, write_json, environment_values


KEYS = ('BLIZZARD_CLIENT_ID', 'BLIZZARD_CLIENT_SECRET')


class RequestLimiter:
    """Share request pacing and an hourly ceiling across collection workers."""

    def __init__(self, requests_per_second=90, hourly_limit=35000):
        self.interval = 1 / requests_per_second
        self.hourly_limit = hourly_limit
        self.starts = deque()
        self.lock = Lock()
        self.next_start = 0

    def acquire(self):
        with self.lock:
            now = time.monotonic()
            while self.starts and self.starts[0] <= now - 3600:
                self.starts.popleft()
            if len(self.starts) >= self.hourly_limit:
                raise RuntimeError('Blizzard collection hourly request budget exhausted')
            time.sleep(max(0, self.next_start - now))
            now = time.monotonic()
            self.starts.append(now)
            self.next_start = now + self.interval


def credentials(env_file):
    values = environment_values(env_file, KEYS)

    if any(not values.get(key) for key in KEYS):
        raise ValueError('Set BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET in .env or the environment; '
                         'see datasources/README.md')

    return values


def links(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'href' and isinstance(child, str):
                yield child
            elif key != '_links':
                yield from links(child)
    elif isinstance(value, list):
        for child in value:
            yield from links(child)


def read_response(url, headers, limiter):
    """Retry transient GET transport failures without bypassing shared request limits."""
    for attempt in range(3):
        limiter.acquire()
        try:
            return read_url_response(url, headers)
        except (TimeoutError, ConnectionError, URLError) as error:
            if isinstance(error, HTTPError) or isinstance(getattr(error, 'reason', None), ssl.SSLError):
                raise
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def fetch(output, values, extra_ids=(), namespace=None, previous=None):
    basic = base64.b64encode((values[KEYS[0]] + ':' + values[KEYS[1]]).encode()).decode()
    token = json.loads(read_url('https://oauth.battle.net/token',
                               {'Authorization': 'Basic ' + basic,
                                'Content-Type': 'application/x-www-form-urlencoded'},
                               b'grant_type=client_credentials'))['access_token']
    requested = namespace or 'static-forever-eu'

    if not re.fullmatch(r'static-(?:[\w.]+-)?forever-eu', requested):
        raise ValueError('Expected a Forever EU static namespace')

    output.mkdir(parents=True)
    manifest = {'state': 'fetching', 'requested_namespace': requested, 'resolved_namespace': None,
                'started_at': datetime.now(timezone.utc).isoformat(), 'locale_parameter': None,
                'resources': {}, 'unavailable': {}}
    limiter = RequestLimiter()
    manifest_lock = Lock()
    cached = {}
    if previous is not None:
        previous_manifest = json.loads((previous / 'manifest.json').read_text())
        if previous_manifest.get('state') != 'complete':
            raise ValueError('Cannot revalidate an incomplete Blizzard snapshot')
        cached = previous_manifest['resources']

    def get(path):
        url = 'https://eu.api.blizzard.com' + path + '?' + urlencode({
            'namespace': manifest['resolved_namespace'] or requested,
        })
        headers = {'Authorization': 'Bearer ' + token}
        prior = cached.get(path, {})
        # Validators belong to the exact URL, including its pinned namespace.
        if prior.get('url') == url:
            for header, conditional in (('Last-Modified', 'If-Modified-Since'), ('ETag', 'If-None-Match')):
                if prior.get('validators', {}).get(header):
                    headers[conditional] = prior['validators'][header]

        try:
            raw, validators = read_response(url, headers, limiter)
            status = 200
        except HTTPError as error:
            if error.code == 304 and any(key in headers for key in ('If-Modified-Since', 'If-None-Match')):
                cached_path = (previous / prior['path']).resolve()
                if not cached_path.is_relative_to(previous.resolve()):
                    raise ValueError('Blizzard cache path leaves its snapshot') from None
                raw = cached_path.read_bytes()
                if hashlib.sha256(raw).hexdigest() != prior['sha256']:
                    raise ValueError('Revalidated Blizzard cache bytes changed') from None
                validators = prior['validators']
                status = 304
            elif error.code == 404:
                manifest['unavailable'][path] = {'status': 404, 'url': url}
                return None
            else:
                raise RuntimeError(f'Blizzard HTTP {error.code} for {path}; stopping without retries') from None

        document = json.loads(raw)
        resolved = parse_qs(urlparse(document['_links']['self']['href']).query)['namespace'][0]

        if not re.fullmatch(r'static-[\w.]+-forever-eu', resolved):
            raise ValueError('Unexpected Blizzard response namespace')

        if namespace and resolved != requested:
            raise ValueError('Blizzard response differs from the requested pinned namespace')

        with manifest_lock:
            if manifest['resolved_namespace'] and manifest['resolved_namespace'] != resolved:
                raise ValueError('Blizzard namespace changed during collection')
            manifest['resolved_namespace'] = resolved
        relative = path.removeprefix('/data/wow/') + '.json'
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
        manifest['resources'][path] = {'path': relative, 'url': url, 'sha256': hashlib.sha256(raw).hexdigest(),
                                       'validators': validators, 'httpStatus': status}

        return document

    try:
        queue = ['/data/wow/quest/index']
        seen = set(queue)
        ids = set(extra_ids)

        for path in queue:
            document = get(path)

            if document is None:
                raise ValueError('Blizzard quest discovery unavailable: ' + path)

            for href in links(document):
                parsed = urlparse(href)
                linked = parsed.path.rstrip('/')

                if parsed.hostname != 'eu.api.blizzard.com':
                    continue

                if re.fullmatch(r'/data/wow/quest/\d+', linked):
                    ids.add(int(linked.rsplit('/', 1)[1]))
                elif re.fullmatch(r'/data/wow/quest/(area|category|type)(/\d+|/index)?', linked):
                    if linked.rsplit('/', 1)[1] in ('area', 'category', 'type'):
                        linked += '/index'

                    if linked not in seen:
                        seen.add(linked)
                        queue.append(linked)

        if not ids:
            raise ValueError('Blizzard discovery returned no quest IDs')

        def collect(quest_id):
            document = get('/data/wow/quest/' + str(quest_id))
            if document is not None and document.get('id') != quest_id:
                raise ValueError('Blizzard returned a different quest ID')

        with ThreadPoolExecutor(max_workers=32) as executor:
            futures = [executor.submit(collect, quest_id) for quest_id in sorted(ids)]
            try:
                for index, future in enumerate(as_completed(futures), 1):
                    future.result()
                    if index % 100 == 0:
                        print(f'Blizzard quests: {index}/{len(ids)}', flush=True)
            except BaseException:
                for future in futures:
                    future.cancel()
                raise

        manifest['state'] = 'complete'
    finally:
        manifest['finished_at'] = datetime.now(timezone.utc).isoformat()
        write_json(output / 'manifest.json', manifest)

    return manifest['resolved_namespace']
