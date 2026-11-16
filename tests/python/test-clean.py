"""Check cleanup boundaries, including local credentials and nested upstream checkouts."""

import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
clean = runpy.run_path(str(ROOT / 'tools/clean.py'))['clean']


class CleanTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory)
        subprocess.run(['git', 'init', '-q', str(root)], check=True)
        (root / 'catalogs').mkdir()
        (root / 'catalogs/record.json').write_text('{}')
        (root / '.env').write_text('LOCAL_CONFIG=keep')
        subprocess.run(['git', 'add', 'catalogs'], cwd=root, check=True)
        return root

    def test_removes_outputs_and_nested_checkouts_without_touching_sources_or_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            for name in ('dist/addon.zip', 'datasources/imports/source/.git/config',
                         'tools/__pycache__/tool.pyc', 'docs/media/curseforge/out/01.jpg'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('disposable')
            self.assertEqual(clean(root, dry_run=True), 4)
            self.assertTrue((root / 'dist/addon.zip').exists())
            self.assertEqual(clean(root), 4)
            self.assertFalse((root / 'datasources/imports').exists())
            self.assertTrue((root / 'catalogs/record.json').exists())
            self.assertEqual((root / '.env').read_text(), 'LOCAL_CONFIG=keep')
            self.assertTrue((root / '.git').is_dir())

    def test_refuses_tracked_output_before_deleting_anything(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            (root / 'dist').mkdir()
            (root / 'dist/kept.txt').write_text('tracked')
            subprocess.run(['git', 'add', 'dist'], cwd=root, check=True)
            with self.assertRaisesRegex(ValueError, 'tracked files'):
                clean(root)
            self.assertTrue((root / 'dist/kept.txt').exists())

    def test_output_symlink_does_not_delete_its_target(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            root = self.fixture(directory)
            target = Path(outside) / 'kept.txt'
            target.write_text('keep')
            (root / 'dist').symlink_to(outside, target_is_directory=True)
            clean(root)
            self.assertTrue(target.exists())
            self.assertFalse((root / 'dist').is_symlink())


if __name__ == '__main__':
    unittest.main()
