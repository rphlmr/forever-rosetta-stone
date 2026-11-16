"""Shared paths, snapshot writing and bounded network reads for source refreshes."""

import json
import subprocess
from pathlib import Path
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def read_url(url, headers=None, data=None):
    return read_url_response(url, headers, data)[0]


def read_url_response(url, headers=None, data=None):
    """Return bounded bytes and cache validators without retaining request secrets."""
    request = Request(url, headers=headers or {}, data=data)

    with urlopen(request, timeout=30) as response:
        content = response.read(128 * 1024 * 1024 + 1)
        if len(content) > 128 * 1024 * 1024:
            raise ValueError('Source response exceeds the snapshot limit')
        validators = {key: response.headers[key] for key in ('Last-Modified', 'ETag')
                      if response.headers.get(key)}
        return content, validators


def latest_revision(repository):
    result = subprocess.run(['git', 'ls-remote', repository, 'HEAD'], check=True, capture_output=True,
                            text=True, timeout=60)
    revision = result.stdout.split()[0]

    if len(revision) != 40 or any(character not in '0123456789abcdef' for character in revision):
        raise ValueError('Expected a Git commit SHA for ' + repository)

    return revision


def environment_values(env_file, keys):
    """Read selected .env values as data, with environment overrides; never execute shell text."""
    import os
    import shlex
    values = {}
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            key, separator, value = line.removeprefix('export ').partition('=')
            if separator and key.strip() in keys:
                parsed = shlex.split(value, comments=True)
                if len(parsed) != 1:
                    raise ValueError('Expected one .env value for ' + key.strip())
                values[key.strip()] = parsed[0]
    values.update({key: os.environ[key] for key in keys if key in os.environ})
    return values
