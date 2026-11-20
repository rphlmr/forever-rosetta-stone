"""Official API prose and native game templates agree without freezing API values."""
import contextlib
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from live_value_harness import LiveValueHarness, ROOT

sys.path.insert(0, str(ROOT))
from tools.catalogs.rendered_spell_templates import infer_leading_percentage, match_template
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps


class CapturedApiSpellTemplateTests(LiveValueHarness, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads((ROOT / 'tests/fixtures/blizzard-maelstrom-rendered-evidence.json').read_text())
        cls.known = cls.evidence['knownNativeTemplates']
        cls.prior = cls.evidence['previousNativeTemplates']
        cls.rendered = {locale: row['document']['description'] for locale, row in cls.evidence['responses'].items()}
        cls.recovered = infer_leading_percentage(cls.known, cls.rendered, cls.prior)
        observations = list(matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'))
        cls.observations = [o for o in observations
                            if o['kind'] == 'spell' and o['id'] == 408498]
        keys = {matrix.fingerprint(o) for o in cls.observations}
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run_observations(observations, Path(directory) / 'report', case_keys=keys)

    def test_all_real_game_variants_pass_all_official_directions(self):
        self.assertTrue(self.report['selectedCases'])
        self.assertLessEqual(set(self.report['counts']), {'passed', 'text_difference_values_preserved'})
        self.assertEqual(sum(self.report['counts'].values()), self.report['selectedCases'] * 90)
        self.assertFalse(self.report['failures'])
        # The real game captured different weapon-dependent chances; the web API
        # snapshot's 5% cannot replace either of these native displayed values.
        bodies = [row.get('leftText', '') for o in self.observations
                  for row in gaps.clean(o['data'])['lines'] if row['type'] == 34]
        self.assertTrue(any('9%' in text for text in bodies))
        self.assertTrue(any('28%' in text for text in bodies))

    def test_native_templates_confirm_reconstructed_fields(self):
        owner = json.loads((ROOT / 'catalogs/spells/408498.json').read_text())['locales']
        for locale, template in self.recovered.items():
            self.assertEqual(owner[locale]['description'], template)
            meta = owner[locale]['translationMetadata']['fields']['description']
            self.assertEqual(meta, {'origin': 'original', 'source': 'wago',
                                    'sourceBuild': '1.60.1.70959', 'sourceLocale': locale})
        for locale, original in self.known.items():
            self.assertEqual(owner[locale]['description'], original)

    def test_all_ten_official_api_bodies_decode_without_becoming_client_captures(self):
        self.assertFalse(self.evidence['source']['nativeClientCapture'])
        for source, text in self.rendered.items():
            for target in set(self.rendered) - {source}:
                with self.subTest(source=source, target=target):
                    self.assertIsNotNone(self.capture(408498, text, source, target))

    def test_each_native_witness_predicts_the_same_missing_templates(self):
        # Leave one known language out, then reconstruct it from the others using
        # that language's own shortened template. Compare byte-for-byte with the
        # withheld native template, normalizing only the duration unit in API prose.
        for locale in self.known:
            witnesses = {key: value for key, value in self.known.items() if key != locale}
            tokens, parts, _ = match_template(self.known[locale], self.rendered[locale])
            # Remove the API's first quantity/wording prefix using an existing
            # target tail; this is a fault-injected derivative, not a native source.
            shortened = parts[0] + ''.join(token + part for token, part in zip(tokens[1:], parts[2:]))
            recovered = infer_leading_percentage(witnesses, self.rendered, {locale: shortened})[locale]
            self.assertEqual(recovered, self.known[locale])

    def test_disagreement_missing_quantity_and_reordered_tail_are_rejected(self):
        known = copy.deepcopy(self.known)
        known['enUS'] = known['enUS'].replace('$m1', '$m2')
        with self.assertRaises(ValueError):
            infer_leading_percentage(known, self.rendered, self.prior)
        for locale in self.prior:
            rendered = copy.deepcopy(self.rendered)
            rendered[locale] = rendered[locale].replace('20', '21', 1)
            with self.assertRaises(ValueError):
                infer_leading_percentage(self.known, rendered, self.prior)
            prior = copy.deepcopy(self.prior)
            prior[locale] = prior[locale].replace('$m1', '$s3', 1)
            with self.assertRaises(ValueError):
                infer_leading_percentage(self.known, self.rendered, prior)


if __name__ == '__main__':
    unittest.main()
