"""Full aura renderer coverage from actual automatic samples and a native hover."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from audit_tooltip_hovers import restore
from replay_aura_campaign import replay_capture


class CapturedAuraTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/auras-1.60.1.70938-enUS.json').read_text()))

    def test_every_actual_aura_sample_resolves_its_instance_and_translates_completely(self):
        original = copy.deepcopy(self.capture)
        report = replay_capture(self.capture)
        self.assertEqual(report['total'], 6)
        self.assertEqual(report['counts'], {'passed': 6}, report)
        self.assertEqual({row['id'] for row in report['observations']}, {6074, 460939, 20217})
        renew = [row for row in report['observations'] if row['id'] == 6074]
        self.assertEqual({row['kind'] for row in renew}, {'aura', 'hover'})
        for row in renew:
            self.assertIn('Soigne 18 points de dégâts toutes les 3 secondes.', row['rendered'])
        self.assertIn('15 secondes restantes', renew[0]['rendered'])
        self.assertIn('14 secondes restantes', renew[1]['rendered'])
        self.assertEqual(self.capture, original)

    def test_expired_or_changed_instance_is_reported_as_missing_context(self):
        capture = copy.deepcopy(self.capture)
        direct = capture['runs'][0]['samples'][2]
        direct['details']['byInstance']['values'][1] = '<nil>'
        capture['runs'][0]['samples'] = [direct]
        report = replay_capture(capture)
        self.assertEqual(report['counts'], {'missing_context': 1})

    def test_hover_cannot_translate_using_a_different_spell_owner(self):
        capture = copy.deepcopy(self.capture)
        hover = capture['runs'][0]['samples'][-1]
        hover['details']['entityID'] = capture['runs'][0]['samples'][0]['details']['aura']['values'][1]['spellId']
        capture['runs'][0]['samples'] = [hover]
        report = replay_capture(capture)
        self.assertEqual(report['counts'], {'error': 1}, report)
        self.assertIn('does not resolve', report['observations'][0]['error'])


if __name__ == '__main__':
    unittest.main()
