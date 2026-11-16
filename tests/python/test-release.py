"""Check release-note isolation, archive boundaries, version checks, and release workflow."""

import runpy
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[2]
release = runpy.run_path(str(ROOT / 'tools/release/build-release.py'))
CATALOG = 'fixture-catalog'
PACK = 'ForeverRosettaStone_Data_enUS'
NOTES = (
    '# Changelog\n\n## [Unreleased]\n\n- Future change.\n\n'
    '## [0.7.0] - 2026-11-11\n\n### Fixed\n\n- Fixed hover text.\n\n## [0.6.0]\n\n- Old change.\n'
)


def create_fixture(root):
    files = {
        'tools/build/addon-manifest.toc': '## Version: 0.7.0\n',
        'CHANGELOG.md': NOTES,
        'LICENSE.md': 'Original project license',
        'ForeverRosettaStone/ForeverRosettaStone.toc': (
            f'## Version: 0.7.0\n## X-Rosetta-Catalog: {CATALOG}\n'
            f'## X-Rosetta-Packs: ~2~\n## X-Rosetta-Packs-1: {PACK[:20]}\n'
            f'## X-Rosetta-Packs-2: {PACK[20:]}\ncore.lua\n'),
        'ForeverRosettaStone/core.lua': 'local addon = ...',
        'ForeverRosettaStone/Bindings.xml': '<Bindings/>',
        'ForeverRosettaStone/THIRD-PARTY.md': 'Credits',
        'ForeverRosettaStone/notices/license.md': 'License',
        'ForeverRosettaStone/media/icon.tga': 'artwork',
        'ForeverRosettaStone/diagnostics/dev-debug.lua': 'local debug = true',
        'ForeverRosettaStone/diagnostics/dev-api-probe.lua': 'local probe = true',
        'ForeverRosettaStone/diagnostics/dev-benchmark.lua': 'local profiler = true',
        'ForeverRosettaStone/unused.lua': 'local unused = true',
        f'ForeverRosettaStone_Data/enUS/{PACK}.toc': f'## X-Rosetta-Catalog: {CATALOG}\n\ndata.lua\n',
        f'ForeverRosettaStone_Data/enUS/data.lua': 'local records = {}',
        'tools/private.txt': 'Never ship',
        'references/capture.txt': 'Never ship',
    }

    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')


class ReleaseTests(unittest.TestCase):
    def test_notes_contain_only_selected_release(self):
        self.assertEqual(release['extract_notes'](NOTES, '0.7.0'),
                         '## 0.7.0\n\n### Fixed\n\n- Fixed hover text.\n')

    def test_empty_unreleased_is_allowed_after_a_release(self):
        self.assertEqual(release['extract_notes']('# Changelog\n\n## [Unreleased]\n\n## [0.7.0]\n- First release.\n',
                                                'Unreleased'), '## Unreleased\n\nNo unreleased changes.\n')

    def test_missing_duplicate_or_empty_release_is_rejected(self):

        for text in (NOTES, '## [1.0.0]\n\n### Fixed\n', '## [1.0.0]\n- One\n## [1.0.0]\n- Two\n'):

            with self.assertRaises(ValueError):
                release['extract_notes'](text, '1.0.0')

    def test_archive_includes_packs_artwork_and_licenses_without_developer_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            create_fixture(root)
            archive = release['build_release'](root, root / 'dist', 'v0.7.0')

            with ZipFile(archive) as bundle:
                names = set(bundle.namelist())
                self.assertIn(f'{PACK}/data.lua', names)
                self.assertFalse(any(name.startswith('ForeverRosettaStone_Data/') for name in names))
                self.assertIn('ForeverRosettaStone/Bindings.xml', names)
                self.assertIn('ForeverRosettaStone/media/icon.tga', names)
                self.assertIn('ForeverRosettaStone/notices/license.md', names)
                self.assertEqual(bundle.read('ForeverRosettaStone/LICENSE.md'), b'Original project license')
                self.assertEqual(len(names), 9)

            self.assertNotIn('Future change', (root / 'dist/release-notes.md').read_text())

    def test_compact_rules_and_language_directories_map_to_installed_addons(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            create_fixture(root)
            toc = root / 'ForeverRosettaStone/ForeverRosettaStone.toc'
            toc.write_text(toc.read_text().replace(PACK[20:] + '\n', PACK[20:] + ',ForeverRosettaStone_Rules\n'))
            rules = root / 'ForeverRosettaStone_Data/Rules'
            rules.mkdir()
            (rules / 'ForeverRosettaStone_Rules.toc').write_text(f'## X-Rosetta-Catalog: {CATALOG}\n\ndata.lua\n')
            (rules / 'data.lua').write_text('local rules = {}')
            archive = release['build_release'](root, root / 'dist', 'v0.7.0')
            with ZipFile(archive) as bundle:
                names = set(bundle.namelist())
                self.assertIn('ForeverRosettaStone_Rules/data.lua', names)
                self.assertIn(PACK + '/data.lua', names)
                self.assertFalse(any(name.startswith('ForeverRosettaStone_Data/') for name in names))
                self.assertEqual(len(names), 11)

    def test_wrong_tag_and_mismatched_catalog_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            create_fixture(root)

            with self.assertRaisesRegex(ValueError, 'TOC version'):
                release['build_release'](root, root / 'dist', 'v0.8.0')

            (root / 'ForeverRosettaStone_Data' / 'enUS' / f'{PACK}.toc').write_text('## X-Rosetta-Catalog: wrong\n')

            with self.assertRaisesRegex(ValueError, 'Catalog version mismatch'):
                release['build_release'](root, root / 'dist', 'v0.7.0')

    def test_debug_manifest_and_missing_runtime_files_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            create_fixture(root)
            toc = root / 'ForeverRosettaStone/ForeverRosettaStone.toc'
            original = toc.read_text()
            for name in ('dev-debug', 'dev-api-probe', 'dev-benchmark'):
                with self.subTest(module=name):
                    toc.write_text(original + f'diagnostics/{name}.lua\n')
                    with self.assertRaisesRegex(ValueError, 'Non-release manifest'):
                        release['collect_files'](root)

            toc.write_text(original)
            (root / 'ForeverRosettaStone/core.lua').unlink()

            with self.assertRaisesRegex(ValueError, 'Missing or unsafe'):
                release['collect_files'](root)


if __name__ == '__main__':
    unittest.main()
