"""Normalize supported token syntax without claiming broken native input is decodable."""
import contextlib
from collections import Counter
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from live_value_harness import LiveValueHarness, ROOT
sys.path.insert(0, str(ROOT))
from tools.catalogs.rendered_spell_templates import infer_conditional_grammar
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix


class CapturedConditionalSourceRepairTests(LiveValueHarness, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads((ROOT / 'tests/fixtures/blizzard-conditional-source-evidence.json').read_text())
        ids = {case['id'] for case in cls.evidence['cases']}
        observations = list(matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'))
        keys = {matrix.fingerprint(o) for o in observations if o['kind'] == 'spell' and o['id'] in ids}
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run_observations(observations, Path(directory) / 'report', case_keys=keys)

    def test_existing_game_captures_have_no_remaining_conditional_decoder_failures(self):
        self.assertTrue(self.report['selectedCases'])
        for failure in self.report['failures']:
            self.assertIn(failure['status'], {'missing_captured_player_context', 'blocked_source_generation'})
        self.assertEqual(sum(self.report['counts'].values()), self.report['nativeStatus']['replayed'] * 90)

    def test_owned_templates_retain_all_prose_values_and_explicit_derivation(self):
        for case in self.evidence['cases']:
            with self.subTest(entity=case['id']):
                result = infer_conditional_grammar(case['knownNativeTemplates'], case['originalTemplate'])
                owner = json.loads((ROOT / f'catalogs/spells/{case["id"]}.json').read_text())['locales']
                self.assertEqual(owner[case['locale']]['description'], result['template'])
                old, new = Counter(case['originalTemplate']), Counter(result['template'])
                self.assertFalse(old - new)
                self.assertIn(dict(new - old), ({}, {']': 1}))
                meta = owner[case['locale']]['translationMetadata']['fields']['description']
                self.assertEqual(meta['tokenDerivation'], 'unanimousConditionalGrammarRepair')
                self.assertEqual(meta['originalTemplateSha256'], hashlib.sha256(case['originalTemplate'].encode()).hexdigest())
                self.assertEqual(set(meta['tokenTemplateLocales']), set(case['knownNativeTemplates']))
                for locale, template in case['knownNativeTemplates'].items():
                    self.assertEqual(owner[locale]['description'], template)

    def test_official_api_exposes_the_broken_source_and_it_stays_unresolved(self):
        case = next(c for c in self.evidence['cases'] if c['locale'] == 'koKR')
        native = case['api']['koKR']['description']
        self.assertIn('s442543[20][10', native)
        self.assertFalse(self.evidence['source']['nativeClientCapture'])
        for target in set(case['api']) - {'koKR'}:
            self.assertIsNone(self.capture(case['id'], native, 'koKR', target))
        # A template normalization must not silently select 10 or 20 from the
        # malformed response. The renderer's ordinary native fallback still owns it.

    def test_nine_valid_official_api_sources_decode_to_every_other_official_target(self):
        case = next(c for c in self.evidence['cases'] if c['locale'] == 'koKR')
        for source in set(case['api']) - {'koKR'}:
            for target in set(case['api']) - {source}:
                with self.subTest(source=source, target=target):
                    self.assertIsNotNone(self.capture(case['id'], case['api'][source]['description'], source, target))

    def test_complete_conditions_and_disagreeing_witnesses_are_not_rewritten(self):
        for case in self.evidence['cases']:
            known = case['knownNativeTemplates']
            with self.assertRaises(ValueError):
                infer_conditional_grammar(known, known['enUS'])
            mutated = copy.deepcopy(known)
            mutated['enUS'] = mutated['enUS'].replace('$s1]', '$s2]')
            with self.assertRaises(ValueError):
                infer_conditional_grammar(mutated, case['originalTemplate'])
            # Fault injection in real source evidence, not a new native capture.
            with self.assertRaises(ValueError):
                infer_conditional_grammar(known, case['originalTemplate'].replace('$s1', '$s2'))


if __name__ == '__main__':
    unittest.main()
