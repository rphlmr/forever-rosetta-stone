"""Upload a prepared release using the CurseForge author Upload API."""

import json
import os
import re
import subprocess
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


def create_metadata(version, notes, game_versions):

    if not re.fullmatch(r'[1-9]\d*(?:,[1-9]\d*)*', game_versions):
        raise ValueError('CURSEFORGE_GAME_VERSION_IDS must contain comma-separated numeric CurseForge IDs')

    return {
        'changelog': notes,
        'changelogType': 'markdown',
        'displayName': f'Forever Rosetta Stone {version}',
        'gameVersions': [int(value) for value in game_versions.split(',')],
        'releaseType': 'release',
    }


def main():
    project = os.environ['CURSEFORGE_PROJECT_ID']
    token = os.environ['CURSEFORGE_API_TOKEN']

    if not re.fullmatch(r'[1-9]\d*', project) or not token or '\n' in token or '\r' in token:
        raise ValueError('Set a numeric CURSEFORGE_PROJECT_ID and a valid CURSEFORGE_API_TOKEN')

    tag = os.environ['RELEASE_TAG']

    if not re.fullmatch(r'v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)', tag):
        raise ValueError('RELEASE_TAG must be vMAJOR.MINOR.PATCH')

    archive = Path('dist') / f'ForeverRosettaStone-{tag[1:]}.zip'
    notes = Path('dist/release-notes.md').read_text(encoding='utf-8')
    metadata = create_metadata(tag[1:], notes, os.environ['CURSEFORGE_GAME_VERSION_IDS'])
    subprocess.run([
        'curl', '--fail-with-body', '--silent', '--show-error', '--max-time', '180',
        '--header', '@-', '--form-string', 'metadata=' + json.dumps(metadata),
        '--form', f'file=@{archive}',
        f'https://wow.curseforge.com/api/projects/{project}/upload-file',
    ], input=f'X-Api-Token: {token}\n', text=True, check=True, timeout=190)


if __name__ == '__main__':
    main()
