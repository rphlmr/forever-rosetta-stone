"""Replay the targeted native German API capture, without fabricated client context."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from audit_tooltip_hovers import restore


class CapturedGermanTooltipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture = ROOT / 'tests/fixtures/tooltip-campaign/targeted-deDE-70938.json'
        cls.capture = restore(json.loads(fixture.read_text()))
        (ROOT / 'datasources/imports').mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            directory = Path(directory)
            fixtures = directory / 'fixtures'
            fixtures.mkdir()
            shutil.copy2(fixture, fixtures)
            cls.observations = list(matrix.observations(fixtures))
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run(fixtures, directory / 'report')

    def test_finished_native_capture_keeps_real_player_context(self):
        self.assertEqual(self.capture['source']['locale'], 'deDE')
        self.assertEqual(len(self.capture['source']['captureSha256']), 64)
        run = self.capture['runs'][0]
        self.assertEqual(run['stoppedReason'], 'api complete')
        self.assertEqual(len(run['samples']), 1)
        sample = run['samples'][0]
        self.assertFalse(sample['details']['pendingAtCapture'])
        self.assertEqual({(o['kind'], o['id']) for o in self.observations},
                         {('spell', 693), ('spell', 10139), ('spell', 428878),
                          ('spell', 451439), ('item', 23309)})
        for observation in self.observations:
            self.assertEqual(observation['calls']['UnitSex']['"player"'], sample['context']['sex'])
            self.assertEqual(observation['calls']['UnitFactionGroup']['"player"'], sample['context']['faction'])

    def test_attached_duration_and_fresh_context_roundtrip_in_all_official_directions(self):
        self.assertEqual(self.report['directionsPerCase'], 90)
        self.assertEqual(self.report['selectedCases'], 6)
        self.assertEqual(sum(self.report['counts'].values()), 540)
        self.assertEqual(self.report['nativeStatus'], {'replayed': 6})
        self.assertFalse(self.report['failures'])
        self.assertFalse([event for event in self.report['failures']
                          if event['status'] == 'missing_captured_player_context'])
        native = next(o for o in self.observations if o['id'] == 428878)
        text = str(gaps.clean(native['data']))
        self.assertIn('30 Sek.lang', text)
        self.assertIn('96 und 141', text)


if __name__ == '__main__':
    unittest.main()
