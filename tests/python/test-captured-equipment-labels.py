"""Native mask/format composition covers captured equipment signatures in every official locale."""
import contextlib
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from derived_tooltip_rows import derive


class CapturedEquipmentLabelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.observations = list(matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'))
        keys = {matrix.fingerprint(o) for o in cls.observations
                if o['kind'] == 'spell' and o['id'] in (14284, 3674, 5938)}
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run_observations(cls.observations, Path(directory) / 'report', case_keys=keys)

    def test_captured_signature_owners_pass_all_official_directions(self):
        self.assertEqual(self.report['directionsPerCase'], 90)
        self.assertTrue(self.report['selectedCases'])
        self.assertFalse(self.report['failures'])
        self.assertEqual(sum(self.report['counts'].values()), self.report['selectedCases'] * 90)

    def test_composed_labels_retain_native_component_provenance(self):
        for entity in (14284, 3674, 5938):
            owner = json.loads((ROOT / f'catalogs/spells/{entity}.json').read_text())
            for locale in matrix.OFFICIAL_LOCALES - {'enUS', 'frFR'}:
                with self.subTest(entity=entity, locale=locale):
                    field = owner['locales'][locale]
                    self.assertTrue(field['equipmentRequirement'])
                    meta = field['translationMetadata']['fields']['equipmentRequirement']
                    self.assertEqual(meta['origin'], 'original')
                    self.assertEqual(meta['sourceLocale'], locale)
                    self.assertEqual(meta['sourceTable'], 'ItemSubClassMask')
                    self.assertEqual(meta['sourceFormatGlobalStringID'], 9871)

    def test_derived_russian_unspaced_format_keeps_the_same_owned_mask(self):
        observation = next(o for o in self.observations if o['kind'] == 'spell' and o['id'] == 14284 and o['locale'] == 'enUS')
        original = copy.deepcopy(observation)
        native = gaps.Replay('enUS', {k: v for k, v in observation['globals'].items() if v != '<nil>'},
                             observation['calls'], observation.get('types'))
        missing, error, _ = native.run('spell', observation['id'], gaps.clean(observation['data']), 'ruRU',
                                      gaps.clean(observation.get('processing')), observation.get('visible'))
        self.assertEqual(missing, [])
        self.assertIsNone(error)
        rows, error = matrix.read_rendered(native)
        self.assertIsNone(error)
        data, issue = derive(gaps.clean(observation['data']), rows,
            matrix.copied_rows(native.lua.globals().ReplayOutputBindings),
            matrix.copied_rows(native.lua.globals().ReplaySuppressions))
        self.assertIsNone(issue)
        source_format = json.loads((ROOT / 'catalogs/globalstrings/9871.json').read_text())['locales']['ruRU']['name']
        alternate = json.loads((ROOT / 'catalogs/globalstrings/9874.json').read_text())['locales']['ruRU']['name']
        prefix, suffix = source_format.split('%s')
        changed = 0
        for row in data['lines']:
            if row.get('requirementType') != 9:
                continue
            value = row['leftText']
            self.assertTrue(value.startswith(prefix))
            body = value[len(prefix):len(value) - len(suffix) if suffix else None]
            row['leftText'] = alternate.replace('%s', body)
            changed += 1
        self.assertEqual(changed, 1)
        reverse = gaps.Replay('ruRU', {}, observation['calls'], observation.get('types'))
        missing, error, _ = reverse.run('spell', observation['id'], data, 'enUS', gaps.clean(observation.get('processing')))
        self.assertEqual(missing, [])
        self.assertIsNone(error)
        self.assertEqual(observation, original)


if __name__ == '__main__':
    unittest.main()
