"""Verified form identities reuse native casting-spell names without runtime exceptions."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from audit_tooltip_hovers import restore


class CapturedFormNameReuseTests(unittest.TestCase):
    def test_missing_form_labels_keep_exact_native_text_and_relation_provenance(self):
        for form, spell, locale in ((1, 768, 'zhTW'), (8, 9634, 'esES')):
            with self.subTest(form=form, locale=locale):
                owner = json.loads((ROOT / f'catalogs/shapeshiftforms/{form}.json').read_text())
                cast = json.loads((ROOT / f'catalogs/spells/{spell}.json').read_text())
                self.assertEqual(owner['locales'][locale]['name'], cast['locales'][locale]['name'])
                self.assertEqual(owner['locales']['enUS']['name'], cast['locales']['enUS']['name'])
                meta = owner['locales'][locale]['translationMetadata']['fields']['name']
                self.assertEqual(meta['origin'], 'original')
                self.assertEqual(meta['sourceTable'], 'SpellName')
                self.assertEqual(meta['sourceRecordID'], spell)
                self.assertEqual(meta['sourceRelationTable'], 'SpellEffect')
                self.assertEqual(meta['sourceRelationFormID'], form)

    def test_captured_cat_form_requirement_translates_to_traditional_chinese(self):
        capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/talent-1322605-enUS.json').read_text()))
        replay = gaps.Replay('enUS', {})
        missing, error, _ = replay.run('spell', capture['data']['id'], gaps.clean(capture['data']), 'zhTW',
                                      gaps.clean(capture['processingInfo']), matrix.visible(capture['visible']))
        self.assertIsNone(error)
        self.assertEqual(missing, [])
        rows, error = matrix.read_rendered(replay)
        self.assertIsNone(error)
        self.assertIn('獵豹形態', ' '.join(row['left'] or '' for row in rows))

    def test_captured_bear_requirement_translates_to_spanish(self):
        observation = next(o for o in matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign')
                           if o['kind'] == 'spell' and o['id'] == 5229 and o['locale'] == 'frFR')
        replay = gaps.Replay('frFR', {k: v for k, v in observation['globals'].items() if v != '<nil>'},
                             observation['calls'], observation.get('types'))
        missing, error, _ = replay.run('spell', observation['id'], gaps.clean(observation['data']), 'esES',
                                      gaps.clean(observation.get('processing')), observation.get('visible'))
        self.assertIsNone(error)
        self.assertEqual(missing, [])
        rows, error = matrix.read_rendered(replay)
        self.assertIsNone(error)
        self.assertIn('Forma de oso nefasto', ' '.join(row['left'] or '' for row in rows))


if __name__ == '__main__':
    unittest.main()
