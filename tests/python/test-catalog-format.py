"""Protect canonical formatting and exact catalog values."""

import json
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FORMAT = runpy.run_path(str(ROOT / 'tools/catalogs/format-catalogs.py'))


class CatalogFormatTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / 'catalogs/quests/1.json'
        self.path.parent.mkdir(parents=True)

    def test_write_preserves_text_metadata_numbers_and_array_order(self):
        value = {'z': [2, 1, 0.5, 1.0], 'locales': {'frFR': {
            'description': 'Épreuve 汉字\n\n  Keep spaces  $s1 {name}\t',
            'translationMetadata': {'source': 'questie', 'origin': 'community'}}},
            'a': {'empty': '', 'array': [], 'null': None, 'bool': True}}
        self.path.write_text(json.dumps(value, ensure_ascii=True))
        result = FORMAT['format_catalogs'](self.root, write=True)
        self.assertEqual(result['writtenFiles'], 1)
        self.assertEqual(json.loads(self.path.read_bytes()), value)
        self.assertEqual(self.path.read_bytes(), FORMAT['dump_json'](value).encode('utf-8'))
        self.assertEqual(FORMAT['format_catalogs'](self.root, write=True)['changedFiles'], 0)

    def test_check_reports_formatting_without_writing(self):
        raw = b'{"z": 1, "a": 2}'
        self.path.write_bytes(raw)
        result = FORMAT['format_catalogs'](self.root)
        self.assertEqual((result['changedFiles'], result['writtenFiles']), (1, 0))
        self.assertEqual(self.path.read_bytes(), raw)

    def test_metadata_is_checked_and_single_file_scope_is_respected(self):
        self.path.write_text('{}')
        config = self.path.parent / 'metadata.json'
        config.write_text('{}')
        self.assertEqual(FORMAT['format_catalogs'](self.root)['checkedFiles'], 2)
        FORMAT['format_catalogs'](self.root, [config], write=True)
        self.assertEqual(config.read_text(), '{}\n')
        self.assertEqual(self.path.read_text(), '{}')

    def test_duplicate_keys_fail_without_losing_text(self):
        raw = b'{"name": "First", "name": "Second"}'
        self.path.write_bytes(raw)
        with self.assertRaisesRegex(ValueError, 'Duplicate JSON key'):
            FORMAT['format_catalogs'](self.root, write=True)
        self.assertEqual(self.path.read_bytes(), raw)

    def test_paths_outside_catalogs_are_rejected(self):
        outside = self.root / 'outside.json'
        outside.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'under catalogs/'):
            FORMAT['format_catalogs'](self.root, [outside], write=True)
        self.assertEqual(outside.read_text(), '{}')


if __name__ == '__main__':
    unittest.main()
