"""Prepare the maintained addon version and its changelog section."""

import argparse
import re
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VERSION_PATTERN = r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)'
CHANGELOG_SECTION = re.compile(r'^## \[([^\]]+)\][^\n]*$', re.MULTILINE)
BUMP_INDEX = {'major': 0, 'minor': 1, 'patch': 2}


def read_version(root):
    template = (root / 'tools/build/addon-manifest.toc').read_text(encoding='utf-8')
    match = re.search(r'^## Version: (' + VERSION_PATTERN + r')$', template, re.MULTILINE)

    if not match:
        raise ValueError('Expected a numeric major.minor.patch Version in tools/build/addon-manifest.toc')

    return match[1]


def extract_notes(changelog, heading):
    """Extract exactly one release section, excluding other releases and maintainer instructions."""
    sections = list(CHANGELOG_SECTION.finditer(changelog))
    matches = [index for index, section in enumerate(sections) if section[1] == heading]

    if len(matches) != 1:
        raise ValueError(f'Expected exactly one CHANGELOG.md section for [{heading}]')

    index = matches[0]
    end = sections[index + 1].start() if index + 1 < len(sections) else len(changelog)
    body = changelog[sections[index].end():end].strip()

    if heading == 'Unreleased' and not body:
        return '## Unreleased\n\nNo unreleased changes.\n'

    if not re.search(r'^- \S', body, re.MULTILINE):
        raise ValueError(f'Changelog section [{heading}] needs at least one player-facing bullet')

    return f'## {heading}\n\n{body}\n'


def prepare_version(root, bump, release_date):
    """Move pending notes into a new version without touching shipping data."""
    manifest_path = root / 'tools/build/addon-manifest.toc'
    changelog_path = root / 'CHANGELOG.md'
    previous = read_version(root)
    parts = list(map(int, previous.split('.')))
    index = BUMP_INDEX[bump]
    parts[index:] = [parts[index] + 1] + [0] * (len(parts) - index - 1)
    version = '.'.join(map(str, parts))

    changelog = changelog_path.read_text(encoding='utf-8')
    sections = list(CHANGELOG_SECTION.finditer(changelog))
    if not sections or sections[0][1] != 'Unreleased':
        raise ValueError('Expected [Unreleased] as the first changelog section')
    if any(section[1] == version for section in sections):
        raise ValueError(f'Changelog already contains [{version}]')
    notes = extract_notes(changelog, 'Unreleased').partition('\n\n')[2]
    if not re.search(r'^- \S', notes, re.MULTILINE):
        raise ValueError('Expected player-facing notes under [Unreleased]')
    end = sections[1].start() if len(sections) > 1 else len(changelog)
    updated_changelog = (changelog[:sections[0].start()] + '## [Unreleased]\n\n'
                         + f'## [{version}] - {release_date.isoformat()}\n\n'
                         + notes + ('\n' if end < len(changelog) else '') + changelog[end:])
    manifest = manifest_path.read_text(encoding='utf-8')
    updated_manifest, count = re.subn(r'^## Version: ' + re.escape(previous) + r'$',
                                    f'## Version: {version}', manifest, flags=re.MULTILINE)
    if count != 1:
        raise ValueError('Expected a standalone Version line in the manifest')
    manifest_path.write_text(updated_manifest, encoding='utf-8')
    changelog_path.write_text(updated_changelog, encoding='utf-8')
    return version


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bump', choices=BUMP_INDEX)
    parser.add_argument('--root', type=Path, default=ROOT)
    args = parser.parse_args()
    print(prepare_version(args.root, args.bump, date.today()))
