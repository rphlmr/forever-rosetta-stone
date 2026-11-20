"""Build a distribution ZIP and version-specific Markdown notes without publishing."""

import argparse
import re
import shutil
import stat
from pathlib import Path, PurePosixPath

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from zipfile import ZIP_DEFLATED, ZipFile
from tools.build.database_packs import pack_directory
from tools.release.distribution import check_distribution
from tools.release.versioning import extract_notes, read_version


ROOT = Path(__file__).resolve().parents[2]


def pack_inventory(manifest):
    packs = re.findall(r'^## X-Rosetta-Packs(?:-\d+)?: (.+)$', manifest, re.MULTILINE)
    inventory = ''.join(packs[1:]) if packs and packs[0].startswith('~') else ''.join(packs)
    pack_names = inventory.split(',')
    catalog = re.search(r'^## X-Rosetta-Catalog: (.+)$', manifest, re.MULTILINE)

    pack_pattern = r'ForeverRosettaStone_(?:Data_[a-zA-Z]+|Rules)'

    if not catalog or not pack_names or not all(re.fullmatch(pack_pattern, name) for name in pack_names):
        raise ValueError('Missing or invalid generated catalog/pack inventory; build the database first')

    return catalog[1], pack_names


def collect_files(root):
    """Package only manifest entries, implicit bindings, artwork, notices, and declared data packs."""
    addon = root / 'ForeverRosettaStone'
    toc = addon / 'ForeverRosettaStone.toc'
    manifest = toc.read_text(encoding='utf-8')
    catalog, pack_names = pack_inventory(manifest)
    files = {toc, addon / 'Bindings.xml', addon / 'THIRD-PARTY.md', root / 'LICENSE.md'}

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

        if f'## X-Rosetta-Catalog: {catalog}\n' not in pack_toc.read_text(encoding='utf-8'):
            raise ValueError(f'Catalog version mismatch in {name}')

        files.update((pack_toc, pack / 'data.lua'))

    for path in files:

        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f'Missing or unsafe release file: {path}')

    return sorted(files)


def promote_preview(root, output, tag, preview):
    """Publish the bytes of a successful same-commit CI artifact; never rebuild its payload."""
    version = read_version(root)
    if tag != f'v{version}':
        raise ValueError('Promoting a preview requires a tag matching the TOC version')
    notes = extract_notes((root / 'CHANGELOG.md').read_text(encoding='utf-8'), version)
    with ZipFile(preview) as bundle:
        names = bundle.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate file in preview archive')
        for info in bundle.infolist():
            path = PurePosixPath(info.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in info.filename \
                    or str(path) != info.filename or info.is_dir() or stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError('Unsafe preview entry: ' + info.filename)
        toc = 'ForeverRosettaStone/ForeverRosettaStone.toc'
        if toc not in names:
            raise ValueError('Missing main addon TOC in preview archive')
        manifest = bundle.read(toc).decode('utf-8')
        if f'## Version: {version}\n' not in manifest:
            raise ValueError('Preview TOC version differs from the release tag')
        catalog, packs = pack_inventory(manifest)
        required = {toc, 'ForeverRosettaStone/Bindings.xml', 'ForeverRosettaStone/THIRD-PARTY.md',
                    'ForeverRosettaStone/LICENSE.md'}
        for entry in manifest.splitlines():
            if not entry or entry.startswith('#'):
                continue
            path = PurePosixPath(entry.replace('\\', '/'))
            if path.is_absolute() or '..' in path.parts or path.name.startswith('dev-'):
                raise ValueError('Non-release manifest entry: ' + entry)
            required.add('ForeverRosettaStone/' + str(path))
        for pack in packs:
            pack_toc = f'{pack}/{pack}.toc'
            required.update((pack_toc, f'{pack}/data.lua'))
            if pack_toc not in names or f'## X-Rosetta-Catalog: {catalog}\n' not in bundle.read(pack_toc).decode('utf-8'):
                raise ValueError('Catalog version mismatch in ' + pack)
        extras = set(names) - required
        if required - set(names) or any(not name.startswith(('ForeverRosettaStone/media/',
                                                            'ForeverRosettaStone/notices/')) for name in extras):
            raise ValueError('Preview archive differs from its shipping manifest')
        if bundle.testzip() is not None:
            raise ValueError('Corrupt preview archive')
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'ForeverRosettaStone-{version}.zip'
    shutil.copyfile(preview, archive)
    (output / 'release-notes.md').write_text(notes, encoding='utf-8')
    print(f'Promoted {archive} from validated CI preview with {len(names)} files')
    return archive


def build_release(root, output, tag=None, preview=None):
    if preview is not None:
        return promote_preview(root, output, tag, preview)
    version = read_version(root)
    manifest = (root / 'ForeverRosettaStone/ForeverRosettaStone.toc').read_text(encoding='utf-8')

    if f'## Version: {version}\n' not in manifest:
        raise ValueError('Generated TOC version differs from the template; build the database first')

    if tag is not None and tag != f'v{version}':
        raise ValueError(f'Release tag {tag!r} must match TOC version v{version}')

    notes = extract_notes((root / 'CHANGELOG.md').read_text(encoding='utf-8'), version if tag else 'Unreleased')
    check_distribution(root)
    files = collect_files(root)
    output.mkdir(parents=True, exist_ok=True)
    suffix = version if tag else f'{version}-preview'
    archive = output / f'ForeverRosettaStone-{suffix}.zip'

    with ZipFile(archive, 'w', ZIP_DEFLATED) as bundle:

        for path in files:
            relative = path.relative_to(root)

            if relative == Path('LICENSE.md'):
                relative = Path('ForeverRosettaStone/LICENSE.md')
            elif relative.parts[0] == 'ForeverRosettaStone_Data':
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
    parser.add_argument('--from-preview', type=Path, help='Promote an existing CI ZIP unchanged; requires --tag')
    args = parser.parse_args()
    build_release(ROOT, args.output, args.tag, args.from_preview)


if __name__ == '__main__':
    main()
