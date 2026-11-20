"""Reject development collectors and local capture files in shipping addon directories."""

COLLECTOR_MARKERS = ('rosettaquestprobe', 'rosetta-quest-probe', 'rosettascan', 'frsscan', 'frsquestprobereport',
                     'rosettasourceprobe', 'rosetta-source-probe', 'frssource',
                     'rosettatooltipcheck', 'rosetta-tooltip-check', 'frsverify', 'rosettanorthshiredialogue')


def check_distribution(root):
    """Check shipping folders and the maintained TOC template without requiring local scan artifacts."""
    directories = [directory for directory in root.glob('ForeverRosettaStone*') if directory.is_dir()]
    files = [path for directory in directories if directory.is_dir()
             for path in directory.rglob('*') if path.is_file()]
    manifest = root / 'tools/build/addon-manifest.toc'

    if manifest.exists():
        files.append(manifest)

    for path in files:
        relative = path.relative_to(root)
        parts = [part.casefold() for part in relative.parts]

        if ('tools' in parts and path != manifest) or 'references' in parts or 'quest-scan' in parts or 'source-scan' in parts \
                or 'quest-dialogue-pilot' in parts \
                or path.suffix.casefold() == '.wdb':
            raise ValueError('Local scan artifact in distribution: ' + str(relative))

        if path.suffix.casefold() not in ('.lua', '.toc', '.xml'):
            continue

        text = path.read_text(encoding='utf-8').casefold().replace('\\', '/')

        if any(marker in text for marker in COLLECTOR_MARKERS) \
                or any(prefix + scan in text for prefix in ('references/', 'tools/')
                       for scan in ('quest-scan', 'source-scan', 'quest-dialogue-pilot')):
            raise ValueError('Local quest collector in distribution: ' + str(relative))

    return len(files)
