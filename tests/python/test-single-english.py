"""Check the maintained single-English locale contract."""

import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import canonical_locale, canonical_locales


class SingleEnglishTests(unittest.TestCase):
    def test_old_english_locale_is_not_supported(self):
        self.assertEqual(canonical_locale('enUS'), 'enUS')
        with self.assertRaisesRegex(ValueError, 'not supported'):
            canonical_locale('enGB')
        self.assertEqual(canonical_locales(['frFR', 'enGB', 'enUS', 'deDE']), ['frFR', 'enUS', 'deDE'])


if __name__ == '__main__':
    unittest.main()
