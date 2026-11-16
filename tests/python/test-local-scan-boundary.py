"""Keep the local quest collector out of distributable addon directories."""

import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COLLECTOR_MARKERS = ('rosettaquestprobe', 'rosetta-quest-probe', 'rosettascan', 'frsscan', 'frsquestprobereport',
                     'rosettasourceprobe', 'rosetta-source-probe', 'frssource',
                     'rosettatooltipcheck', 'rosetta-tooltip-check', 'frsverify')


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
                or path.suffix.casefold() == '.wdb':
            raise ValueError('Local scan artifact in distribution: ' + str(relative))

        if path.suffix.casefold() not in ('.lua', '.toc', '.xml'):
            continue

        text = path.read_text(encoding='utf-8').casefold().replace('\\', '/')

        if any(marker in text for marker in COLLECTOR_MARKERS) \
                or any(prefix + scan in text for prefix in ('references/', 'tools/')
                       for scan in ('quest-scan', 'source-scan')):
            raise ValueError('Local quest collector in distribution: ' + str(relative))

    return len(files)


class LocalScanBoundaryTests(unittest.TestCase):
    def test_shipping_addons_do_not_contain_the_local_collector(self):
        self.assertGreater(check_distribution(ROOT), 0)

    def test_collector_code_is_rejected_even_when_renamed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            addon = root / 'ForeverRosettaStone'
            addon.mkdir()
            (addon / 'renamed.lua').write_text('RosettaQuestProbeData = {}', encoding='utf-8')

            with self.assertRaisesRegex(ValueError, 'collector in distribution'):
                check_distribution(root)

    def test_source_collector_is_rejected_from_release_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools/build').mkdir(parents=True)
            (root / 'tools/build/addon-manifest.toc').write_text(
                '../tools/source-scan/rosetta-source-probe/probe.lua\n', encoding='utf-8')

            with self.assertRaisesRegex(ValueError, 'collector in distribution'):
                check_distribution(root)

    def test_local_probe_toc_cannot_be_added_to_the_shipping_template(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools/build').mkdir(parents=True)
            (root / 'tools/build/addon-manifest.toc').write_text(
                '../references/quest-scan/rosetta-quest-probe/probe.lua\n', encoding='utf-8')

            with self.assertRaisesRegex(ValueError, 'collector in distribution'):
                check_distribution(root)

    def test_versioned_tools_and_ignored_captures_are_allowed_outside_the_distribution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            references = root / 'references/quest-scan'
            references.mkdir(parents=True)
            (references / 'probe.lua').write_text('RosettaQuestProbeData = {}', encoding='utf-8')
            (references / 'questcache.wdb').write_bytes(b'local cache')
            tools = root / 'tools/quest-scan'
            tools.mkdir(parents=True)
            (tools / 'probe.lua').write_text('RosettaQuestProbeData = {}', encoding='utf-8')
            addon = root / 'ForeverRosettaStone'
            addon.mkdir()
            (addon / 'core.lua').write_text('local addon = ...', encoding='utf-8')
            self.assertEqual(check_distribution(root), 1)


if __name__ == '__main__':
    unittest.main()
