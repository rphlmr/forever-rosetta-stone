"""Build a distribution ZIP and version-specific Markdown notes without publishing."""

import argparse
import re
import runpy
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from zipfile import ZIP_DEFLATED, ZipFile
from tools.build.database_packs import pack_directory


ROOT = Path(__file__).resolve().parents[2]
VERSION_PATTERN = r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)'


def read_version(root):
    template = (root / 'tools/build/addon-manifest.toc').read_text(encoding='utf-8')
    match = re.search(r'^## Version: (' + VERSION_PATTERN + r')$', template, re.MULTILINE)

    if not match:
        raise ValueError('Expected a numeric major.minor.patch Version in tools/build/addon-manifest.toc')

    return match[1]


def extract_notes(changelog, heading):
    """Extract exactly one release section, excluding other releases and maintainer instructions."""
    sections = list(re.finditer(r'^## \[([^\]]+)\][^\n]*$', changelog, re.MULTILINE))
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


def collect_files(root):
    """Package only manifest entries, implicit bindings, artwork, notices, and declared data packs."""
    addon = root / 'ForeverRosettaStone'
    toc = addon / 'ForeverRosettaStone.toc'
    manifest = toc.read_text(encoding='utf-8')
    packs = re.findall(r'^## X-Rosetta-Packs(?:-\d+)?: (.+)$', manifest, re.MULTILINE)
    inventory = ''.join(packs[1:]) if packs and packs[0].startswith('~') else ''.join(packs)
    pack_names = inventory.split(',')
    catalog = re.search(r'^## X-Rosetta-Catalog: (.+)$', manifest, re.MULTILINE)

    pack_pattern = r'ForeverRosettaStone_(?:Data_[a-zA-Z]+|Rules)'

    if not catalog or not pack_names or not all(re.fullmatch(pack_pattern, name) for name in pack_names):
        raise ValueError('Missing or invalid generated catalog/pack inventory; build the database first')

    files = {toc, addon / 'Bindings.xml', addon / 'THIRD-PARTY.md'}

    for entry in manifest.splitlines():

        if not entry or entry.startswith('#'):
            continue

        relative = Path(entry.replace('\\', '/'))

        if relative.is_absolute() or '..' in relative.parts or relative.name.startswith('dev-'):
            raise ValueError(f'Non-release manifest entry: {entry}')

        files.add(addon / relative)

    for directory in ('media', 'notices'):
        files.update(path for path in (addon / directory).rglob('*') if path.is_file())

    for name in pack_names:
        pack = pack_directory(root / 'ForeverRosettaStone_Data', name)
        pack_toc = pack / f'{name}.toc'

        if f'## X-Rosetta-Catalog: {catalog[1]}\n' not in pack_toc.read_text(encoding='utf-8'):
            raise ValueError(f'Catalog version mismatch in {name}')

        files.update((pack_toc, pack / 'data.lua'))

    for path in files:

        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f'Missing or unsafe release file: {path}')

    return sorted(files)


def build_release(root, output, tag=None):
    version = read_version(root)
    manifest = (root / 'ForeverRosettaStone/ForeverRosettaStone.toc').read_text(encoding='utf-8')

    if f'## Version: {version}\n' not in manifest:
        raise ValueError('Generated TOC version differs from the template; build the database first')

    if tag is not None and tag != f'v{version}':
        raise ValueError(f'Release tag {tag!r} must match TOC version v{version}')

    notes = extract_notes((root / 'CHANGELOG.md').read_text(encoding='utf-8'), version if tag else 'Unreleased')
    check_distribution = runpy.run_path(str(ROOT / 'tests/python/test-local-scan-boundary.py'))['check_distribution']
    check_distribution(root)
    files = collect_files(root)
    output.mkdir(parents=True, exist_ok=True)
    suffix = version if tag else f'{version}-preview'
    archive = output / f'ForeverRosettaStone-{suffix}.zip'

    with ZipFile(archive, 'w', ZIP_DEFLATED) as bundle:

        for path in files:
            relative = path.relative_to(root)

            if relative.parts[0] == 'ForeverRosettaStone_Data':
                locale = relative.parts[1]
                name = 'ForeverRosettaStone_Rules' if locale == 'Rules' else 'ForeverRosettaStone_Data_' + locale
                relative = Path(name, *relative.parts[2:])

            bundle.write(path, relative)

    (output / 'release-notes.md').write_text(notes, encoding='utf-8')
    print(f'Built {archive} with {len(files)} files')

    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', help='Exact release tag, e.g. v1.0.0; omitted for an Unreleased preview')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    build_release(ROOT, args.output, args.tag)


if __name__ == '__main__':
    main()
